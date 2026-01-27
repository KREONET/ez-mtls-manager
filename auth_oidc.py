from authlib.integrations.flask_client import OAuth
from flask import url_for
import logging


class OIDCAuthProvider:
    def __init__(self, app=None):
        self.oauth = OAuth()
        if app:
            self.init_app(app)

    def init_app(self, app):
        self.oauth.init_app(app)
        self.oauth.register(
            "oidc",
            client_id=app.config.get("OIDC_CLIENT_ID"),
            client_secret=app.config.get("OIDC_CLIENT_SECRET"),
            client_kwargs={"scope": "openid profile email"},
            server_metadata_url=f'https://{
                app.config.get("OIDC_DOMAIN")}/.well-known/openid-configuration'
        )

    def login(self):
        logging.debug("[OIDC] Initiating login redirect...")
        try:
            redirect_uri = url_for("auth.callback", _external=True)
            logging.debug(f"[OIDC] Generated redirect URI: {redirect_uri}")
            resp = self.oauth.oidc.authorize_redirect(
                redirect_uri=redirect_uri)
            logging.debug("[OIDC] authorize_redirect generated successfully.")
            return resp
        except Exception as e:
            logging.error(f"[OIDC] login failed with error: {e}")
            raise

    def authorize(self):
        token = self.oauth.oidc.authorize_access_token()
        user_info = token.get("userinfo")

        if not user_info or not user_info.get("email"):
            try:
                logging.debug(
                    "[OIDC] Email missing in ID Token. Fetching from UserInfo endpoint...")
                extra_info = self.oauth.oidc.userinfo(token=token)
                if user_info:
                    user_info.update(extra_info)
                else:
                    user_info = extra_info
            except Exception as e:
                logging.warning(
                    f"[OIDC] Failed to fetch UserInfo from endpoint: {e}")

                if not user_info:
                    raise

        logging.debug(f"[OIDC] user_info: {user_info}")
        return user_info
