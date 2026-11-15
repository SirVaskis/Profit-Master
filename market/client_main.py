"""PyInstaller entry point; the client has no server-framework dependency."""

from market.collector import main

if __name__ == "__main__":
    raise SystemExit(main())
