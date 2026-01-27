import os
import subprocess
import logging
import tempfile


class StepClient:
    def __init__(self, step_path="step", ca_url="https://localhost:8443",
                 root_ca_path=None, provisioner_password_file=None):
        self.step_path = step_path
        self.ca_url = ca_url
        self.root_ca_path = root_ca_path
        self.provisioner_password_file = provisioner_password_file

    def _run_command(self, args, env=None):
        """Executes step command and returns (stdout, stderr). Raises exception on error."""
        full_env = os.environ.copy()
        if env:
            full_env.update(env)

        cmd = [self.step_path] + args

        logging.debug(f"Running command: {' '.join(cmd)}")

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                env=full_env,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            logging.error(f"Step command failed: {e.stderr}")
            raise Exception(f"Step CLI Error: {e.stderr}")

    def issue_p12(self, cn, p12_password, valid_hours=24):
        """
        Issues a certificate and bundles it into a P12 file.
        Returns (p12_bytes, serial, expires_at_str, thumb_sha1, thumb_sha256).
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            crt_path = os.path.join(tmp_dir, "cert.crt")
            key_path = os.path.join(tmp_dir, "cert.key")
            p12_path = os.path.join(tmp_dir, "cert.p12")

            # 1. Issue Certificate (CRT + Key)
            # step ca certificate <cn> <crt> <key> --provisioner <name>
            # --not-after <duration>
            issue_args = [
                "ca", "certificate",
                cn, crt_path, key_path,
                "--provisioner", "admin",
                "--not-after", f"{valid_hours}h"
            ]

            if self.provisioner_password_file:
                issue_args.extend(
                    ["--provisioner-password-file", self.provisioner_password_file])

            logging.info("Generate certificate")
            self._run_command(issue_args)

            # 2. Inspect Certificate (Serial, Expiry, etc.)
            info = self.get_certificate_info(crt_path)
            # Log summary
            log_summary = {
                "serial_number": info.get("serial_number"),
                "subject_dn": info.get("subject_dn"),
                "validity.start": info.get("validity", {}).get("start"),
                "validity.end": info.get("validity", {}).get("end")
            }
            logging.info(f"Certificate Info: {log_summary}")
            serial = info.get("serial_number") or info.get("serial")
            not_after = info.get("not_after") or info.get(
                "notAfter") or info.get("validity", {}).get("end")
            not_before = info.get("not_before") or info.get(
                "notBefore") or info.get("validity", {}).get("start")

            # 3. Bundle into P12
            p12_pass_file = os.path.join(tmp_dir, "p12pass.txt")
            with open(p12_pass_file, "w") as f:
                f.write(p12_password)

            # Get fingerprints directly from info
            sha1 = info.get("fingerprint_sha1")
            sha256 = info.get("fingerprint_sha256")

            # macOS Compatibility Fix: Use OpenSSL 3's -legacy flag for P12
            # 'step certificate p12' might not use legacy algorithms required by macOS Keychain.
            # Use openssl directly to ensure compatibility.
            cmd = [
                "openssl", "pkcs12", "-export", "-legacy",
                "-out", p12_path,
                "-inkey", key_path,
                "-in", crt_path,
                "-passout", f"file:{p12_pass_file}"
            ]

            subprocess.run(cmd, check=True, capture_output=True, text=True)

            # Read results
            with open(p12_path, "rb") as f:
                p12_bytes = f.read()

            with open(crt_path, "r") as f:
                crt_pem = f.read()

            return p12_bytes, serial, not_after, not_before, sha1, sha256, crt_pem

    def revoke_certificate(self, serial):
        """
        Revokes a certificate by its serial number.
        """
        # 1. Generate Revoke Token
        # step ca token --revoke <serial> --provisioner <name>
        # --provisioner-password-file <file>
        token_args = [
            "ca", "token",
            "--provisioner-password-file", self.provisioner_password_file,
            "--revoke", serial
        ]
        logging.debug("generate revoke token")
        token = self._run_command(token_args)

        # 2. Revoke using token
        # step ca revoke <serial> --token <token>
        revoke_args = [
            "ca", "revoke",
            "--token", token,
            serial
        ]
        logging.info("Revoke certificate")
        return self._run_command(revoke_args)

    def get_certificate_info(self, crt_file_path):
        """
        Inspects certificate file and returns parsed info (e.g., expiration).
        Useful for parsing a certificate before bundling.
        """
        # step certificate inspect <file> --format json
        cmd = [
            self.step_path,
            "certificate",
            "inspect",
            crt_file_path,
            "--format",
            "json"]
        try:
            result = subprocess.run(
                cmd, check=True, capture_output=True, text=True)
            import json
            return json.loads(result.stdout)
        except Exception as e:
            logging.error(f"Inspect failed: {e}")
            return {}

    def get_crl(self):
        """Fetch Certificate Revocation List (CRL) from Step CA.
        Since the Step CLI version used does not support 'ca crl',
        retrieve DER encoded CRL via CA's REST endpoint and convert to PEM.
        """
        try:
            # Fetch DER encoded CRL from CA's HTTP endpoint
            crl_url = f"{self.ca_url}/crl"
            # Use -k to ignore self-signed cert, pipe to openssl for conversion
            cmd = f"curl -k -s {crl_url} | openssl crl -inform DER -outform PEM"
            crl_pem = subprocess.check_output(cmd, shell=True, text=True)
            return crl_pem
        except Exception as e:
            logging.error(f"Failed to get CRL: {e}")
            raise
