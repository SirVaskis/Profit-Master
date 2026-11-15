"""Generate private configuration without displaying or hardcoding credentials."""

import argparse
import json
import os
from pathlib import Path
import secrets


def create(directory, server_url):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    env_path, client_path = directory / ".env", directory / "client-config.json"
    if env_path.exists() or client_path.exists():
        raise ValueError("Existing configuration preserved; edit it rather than generating new credentials")
    names = ("ADMIN_PASSWORD", "WRITER_PASSWORD", "READER_PASSWORD", "GRAFANA_DB_PASSWORD",
             "GRAFANA_ADMIN_PASSWORD", "GRAFANA_SECRET_KEY", "UPLOAD_TOKEN")
    values = {name: secrets.token_hex(32) for name in names}
    values.update(API_PORT="8787", GRAFANA_PORT="3000", GRAFANA_ROOT_URL="http://localhost:3000/", GRAFANA_ANONYMOUS="false")
    with env_path.open("x", encoding="utf-8") as output:
        output.write("\n".join(f"{key}={value}" for key, value in values.items()) + "\n")
    config = dict(server_url=server_url, token=values["UPLOAD_TOKEN"],
                  game_root="C:/Program Files (x86)/World of Warcraft/_forever_", saved_files=[], poll_seconds=5)
    with client_path.open("x", encoding="utf-8") as output:
        json.dump(config, output, indent=2)
    if os.name != "nt":
        env_path.chmod(0o600)
        client_path.chmod(0o600)
    return values


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).parent)
    parser.add_argument("--server-url", default="http://localhost:8787")
    args = parser.parse_args()
    create(args.directory, args.server_url)
    print("Created private .env and client-config.json. Credentials were not printed.")
