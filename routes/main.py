from flask import Blueprint, render_template, Response, current_app
import settings
import logging

bp = Blueprint('main', __name__)


@bp.route("/")
def index():
    return render_template("index.html")


@bp.route("/step-ca-chain.crt")
def step_ca_chain():
    """
    Provide full CA chain (Intermediate + Root) for client configuration.
    """
    try:
        intermediate_path = settings.STEP_INTERMEDIATE_CA
        root_path = settings.STEP_ROOT_CA

        with open(intermediate_path, "r") as f:
            intermediate = f.read()

        with open(root_path, "r") as f:
            root = f.read()

        # Connect: Intermediate first, then Root
        full_chain = intermediate + "\n" + root

        return Response(full_chain, mimetype="text/plain")

    except Exception as e:
        logging.error(f"Failed to generate CA chain: {e}")
        return f"Error generating chain: {e}", 500


@bp.route("/crl")
@bp.route("/step-ca.crl")
def crl():
    """
    Provide CRL (Certificate Revocation List).
    Servers like Apache need to fetch this list periodically.
    """
    try:
        step_client = current_app.step_client
        crl_pem = step_client.get_crl()
        # Step CA 'ca crl' output is typically PEM.
        # PEM CRL MIME type: application/x-pem-file or text/plain.
        return Response(crl_pem, mimetype="text/plain")
    except Exception as e:
        logging.error(f"Failed to fetch CRL: {e}")
        return f"Error fetching CRL: {e}", 500
