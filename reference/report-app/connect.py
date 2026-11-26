"""Enroll this container using CMDOP's account sign-in commands."""
import argparse
from getpass import getpass
import json
import subprocess
import sys


def signin(*args):
    process = subprocess.run(["cmdop", "signin", *args], stdout=subprocess.PIPE, text=True)
    try:
        reply = json.loads(process.stdout)
    except ValueError:
        raise SystemExit("CMDOP sign-in did not return a response.") from None
    if not isinstance(reply, dict):
        raise SystemExit("Invalid CMDOP sign-in response.")
    if reply.get("error") == "admitted" and reply.get("base_url"):
        return reply
    if process.returncode or "error" in reply:
        raise SystemExit(reply.get("message") or "CMDOP sign-in failed.")
    return reply


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", default="my-product-demo")
    args = parser.parse_args()
    if not sys.stdin.isatty():
        raise SystemExit("First sign-in requires an interactive terminal.")
    # Keep CMDOP's own first-use agreement prompt attached to the terminal.
    if subprocess.run(["cmdop", "config", "set", "name", args.name]).returncode:
        raise SystemExit("CMDOP could not prepare the machine configuration.")
    email = input("Email for your existing CMDOP account: ").strip()
    reply = signin("email", email)
    if reply.get("error") != "admitted":
        reply = signin("code", "--email", email, "--code", getpass("Email code: ").strip())
        if reply.get("state") == "second_factor":
            reply = signin("second-factor", "--attempt", reply["attempt"],
                           "--code", getpass("Authenticator code: ").strip())
    if reply.get("error") != "admitted" and reply.get("state") != "added":
        raise SystemExit("CMDOP has not confirmed enrollment.")
    if reply.get("error") == "admitted":
        print("Reusing this volume's existing registration at", reply["base_url"])
    else:
        print("Registered with", reply["base_url"])


if __name__ == "__main__":
    main()
