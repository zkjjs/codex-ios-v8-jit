#!/usr/bin/env python3
"""Generate consistent, public iOS OAuth build settings. Never accepts a client secret."""
import argparse
import os
from pathlib import Path
import re


def build_config(client_id: str, bundle_id: str) -> dict[str, str]:
    client_id, bundle_id = client_id.strip(), bundle_id.strip()
    if not re.fullmatch(r'[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com', client_id):
        raise ValueError('Google iOS OAuth client ID is missing or invalid; do not use the placeholder.')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle_id):
        raise ValueError('Bundle ID must match the iOS OAuth client and contain no build-setting syntax.')
    return {'GDIRECT_BUNDLE_ID': bundle_id, 'GOOGLE_CLIENT_ID': client_id,
            'GOOGLE_REVERSED_CLIENT_ID': '.'.join(reversed(client_id.split('.')))}


def configure(ios_directory: Path, *, client_id: str, bundle_id: str) -> bool:
    if not client_id.strip():
        return False
    config = build_config(client_id, bundle_id)
    ios_directory.mkdir(parents=True, exist_ok=True)
    output = ios_directory/'Config.local.xcconfig'
    output.write_text('// Generated public OAuth settings; no client secret.\n' + ''.join(f'{key} = {value}\n' for key, value in config.items()))
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client-id', default=os.environ.get('GDIRECT_GOOGLE_CLIENT_ID', ''))
    parser.add_argument('--bundle-id', default=os.environ.get('GDIRECT_BUNDLE_ID', 'org.gdirect.ios'))
    parser.add_argument('--ios-directory', type=Path, default=Path(__file__).resolve().parents[1]/'ios')
    args = parser.parse_args()
    if configure(args.ios_directory, client_id=args.client_id, bundle_id=args.bundle_id):
        print('Google iOS OAuth build settings configured; callback scheme derived automatically.')
    else:
        print('Google login is not configured: provide an iOS OAuth client ID. Public-link downloads remain available.')


if __name__ == '__main__':
    main()
