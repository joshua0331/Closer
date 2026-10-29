"""Administrative CLI; never exposed as an HTTP endpoint."""
import argparse
import json
from demo_security import DemoAccess
from demo_storage import make_records


def main():
    parser = argparse.ArgumentParser(description='Manage private Closer judging-demo access')
    commands = parser.add_subparsers(dest='command', required=True)
    init = commands.add_parser('init')
    init.add_argument('--calls', type=int, default=100)
    init.add_argument('--images', type=int, default=5)
    init.add_argument('--hours', type=int, default=336)
    invite = commands.add_parser('invite')
    invite.add_argument('--label', required=True)
    invite.add_argument('--calls', type=int, default=20)
    invite.add_argument('--images', type=int, default=1)
    invite.add_argument('--hours', type=int, default=336)
    invite.add_argument('--sessions', type=int, default=6)
    revoke = commands.add_parser('revoke')
    revoke.add_argument('--id', required=True)
    for name in ['disable', 'enable', 'status']:
        commands.add_parser(name)
    args = parser.parse_args()
    security = DemoAccess(make_records())
    if args.command == 'init':
        result = security.initialize(args.calls, args.images, args.hours)
    elif args.command == 'invite':
        result = security.create_invite(args.label, args.calls, args.images, args.hours, args.sessions)
        print('PRIVATE CODE: share privately with the judges, never in the public repo.')
    elif args.command == 'revoke':
        security.revoke(args.id)
        result = {'revoked': args.id}
    elif args.command in {'disable', 'enable'}:
        security.set_enabled(args.command == 'enable')
        result = {'enabled': args.command == 'enable'}
    else:
        policy = security.policy()
        result = None if policy is None else {key: value for key, value in policy.items() if key != 'leases'}
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
