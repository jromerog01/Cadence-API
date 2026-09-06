"""User management CLI — there is no self-registration by design (see plan
Fase 8), so this is the only way to create or update a login.

Usage (inside the api container, which has DATABASE_URL set):
    docker compose exec api python -m api.cli create-user \
        alguien@example.com "contraseña-larga" "Nombre Visible"

Re-running with the same email updates the password and display name
(upsert), which also lets you set a password on the `default` user seeded
by the initial migration if you just want a single account.
"""

import argparse
import sys

from adapters.db import new_session
from adapters.postgres_repo import PostgresUserRepository
from api.security import hash_password


def create_user(email: str, password: str, display_name: str) -> None:
    session = new_session()
    try:
        repo = PostgresUserRepository(session)
        user = repo.upsert_user(
            email=email, password_hash=hash_password(password), display_name=display_name
        )
        print(f"ok: {user.email} ({user.id})")
    finally:
        session.close()


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m api.cli")
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create-user", help="Create or update a user's password")
    create_parser.add_argument("email")
    create_parser.add_argument("password")
    create_parser.add_argument("display_name")

    args = parser.parse_args()
    if args.command == "create-user":
        create_user(args.email, args.password, args.display_name)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # surfaced as a CLI error, not a traceback dump
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
