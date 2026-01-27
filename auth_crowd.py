import requests
import base64
import logging


class CrowdAuthProvider:
    def __init__(self, base_url, app_name, app_password):
        self.base_url = base_url
        self.app_name = app_name
        self.app_password = app_password

    def get_auth_header(self):
        auth_header = base64.b64encode(
            f"{self.app_name}:{self.app_password}".encode("utf-8")
        ).decode("utf-8")
        return {
            "Authorization": f"Basic {auth_header}",
            "Accept": "application/json",
            "Content-Type": "application/json"
        }

    def authenticate(self, username, password, remote_addr):
        url = f"{self.base_url}/rest/usermanagement/1/session"
        logging.debug(f"[CROWD] Auth attempt for user: {username}, URL: {url}")

        payload = {
            "username": username,
            "password": password,
            "validation-factors": {
                "validationFactors": [
                    {"name": "remote_address", "value": remote_addr or "127.0.0.1"}
                ]
            },
        }

        try:
            resp = requests.post(
                url, json=payload, headers=self.get_auth_header())
            logging.debug(f"[CROWD] Response status: {resp.status_code}")
            logging.debug(f"[CROWD] Response body: {resp.text}")
            if resp.status_code == 201:
                data = resp.json()
                return True, data.get("token")
            else:
                return False, None
        except Exception as e:
            logging.error(f"[CROWD] Request failed with exception: {e}")
            return False, None

    def get_user_details(self, username):
        url = f"{self.base_url}/rest/usermanagement/1/user?username={username}"
        logging.debug(f"[CROWD] Fetching details for user: {
                      username}, URL: {url}")

        try:
            resp = requests.get(url, headers=self.get_auth_header())
            logging.debug(
                f"[CROWD] User details response status: {
                    resp.status_code}")
            if resp.status_code == 200:
                user_data = resp.json()
                # email = user_data.get("email") # Unused
                return user_data
            elif resp.status_code == 404:
                logging.warning(f"[CROWD] User {username} not found.")
                return None
            else:
                logging.error(
                    f"[CROWD] Failed to fetch user details: {
                        resp.text}")
                return None
        except Exception as e:
            logging.error(f"[CROWD] Exception fetching user details: {e}")
            return None

    def get_user_groups(self, username):
        url = f"{
            self.base_url}/rest/usermanagement/1/user/group/direct?username={username}"
        logging.debug(f"[CROWD] Fetching groups for user: {
                      username}, URL: {url}")

        try:
            resp = requests.get(url, headers=self.get_auth_header())
            logging.debug(
                f"[CROWD] User groups response status: {
                    resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                group_list = [g['name'] for g in data.get('groups', [])]
                logging.debug(f"[CROWD] User groups: {group_list}")
                return group_list
            else:
                logging.error(
                    f"[CROWD] Failed to fetch user groups: {
                        resp.text}")
                return []
        except Exception as e:
            logging.error(f"[CROWD] Exception fetching user groups: {e}")
            return []
