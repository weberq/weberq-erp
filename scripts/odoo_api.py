#!/usr/bin/env python3
"""
WeberQ ERP — command-line client for Odoo's JSON-2 API.

Reads and changes ERP records from a terminal or a script, through
POST /json/2/<model>/<method> with an API key. Output is JSON.

Profiles live in ~/.config/weberq-erp/profiles.ini, e.g.:

    [staging]
    url = http://localhost:18069
    db = weberq_staging
    key_file = ~/.config/weberq-erp/apikey

    [prod]
    url = https://erp.weberq.in
    db = weberq
    key_file = ~/.config/weberq-erp/apikey

The default profile is staging. Calls on prod that may change data need
--yes; reads never do.

Examples:
    odoo_api.py whoami
    odoo_api.py search-read res.partner '[["customer_rank", ">", 0]]' --fields name,vat
    odoo_api.py -p prod count account.move '[["state", "=", "posted"]]'
    odoo_api.py create res.partner '{"name": "Acme"}'
    odoo_api.py write res.partner 42 '{"phone": "+91 ..."}'
    odoo_api.py call account.move action_post --ids 7
    odoo_api.py call sale.order search_read --kw '{"domain": [], "fields": ["name"], "limit": 5}'
    odoo_api.py fields account.move --attrs type,string,relation
    odoo_api.py attach account.bank.statement 3 ./statement.pdf
"""

import argparse
import base64
import configparser
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request

CONFIG = os.path.expanduser(os.environ.get('WEBERQ_ODOO_CONFIG', '~/.config/weberq-erp/profiles.ini'))

# Methods that never change data. Anything else on prod needs --yes.
READ_METHODS = {
    'search', 'search_read', 'search_count', 'read', 'read_group', 'formatted_read_group',
    'web_search_read', 'web_read', 'fields_get', 'name_search', 'default_get', 'get_views',
    'check_access', 'has_access', 'context_get', 'onchange', 'get_formview_action',
    'get_metadata', 'name_get', 'export_data', 'search_fetch', 'fetch',
}


class OdooError(Exception):
    pass


class Odoo:
    def __init__(self, profile):
        cfg = configparser.ConfigParser()
        if not cfg.read(CONFIG):
            raise OdooError(f'no config at {CONFIG}')
        if profile not in cfg:
            raise OdooError(f'unknown profile {profile!r}; known: {", ".join(cfg.sections())}')
        section = cfg[profile]
        self.profile = profile
        self.url = section['url'].rstrip('/')
        self.db = section.get('db')
        key = section.get('key')
        if not key:
            with open(os.path.expanduser(section['key_file'])) as f:
                key = f.read().strip()
        self.key = key

    def call(self, model, method, ids=None, context=None, **kwargs):
        body = dict(kwargs)
        if ids:
            body['ids'] = ids
        if context:
            body['context'] = context
        req = urllib.request.Request(
            f'{self.url}/json/2/{model}/{method}',
            data=json.dumps(body).encode(),
            method='POST',
            headers={
                'Authorization': f'Bearer {self.key}',
                'Content-Type': 'application/json; charset=utf-8',
                'User-Agent': 'weberq-erp-cli',
                **({'X-Odoo-Database': self.db} if self.db else {}),
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                return json.loads(resp.read() or 'null')
        except urllib.error.HTTPError as e:
            raw = e.read().decode(errors='replace')
            try:
                err = json.loads(raw)
                msg = err.get('message') or raw
                name = err.get('name', '')
            except ValueError:
                msg, name = raw[:2000], ''
            raise OdooError(f'HTTP {e.code} {name}: {msg}') from None
        except urllib.error.URLError as e:
            raise OdooError(f'cannot reach {self.url}: {e.reason}') from None


def parse_json(text, default=None):
    if text is None:
        return default
    if text.startswith('@'):
        with open(text[1:]) as f:
            return json.load(f)
    return json.loads(text)


def parse_ids(text):
    return [int(i) for i in str(text).split(',') if i.strip()]


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0], formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog='\n\n'.join(__doc__.split('\n\n')[1:]))
    p.add_argument('-p', '--profile', default=os.environ.get('WEBERQ_ODOO_PROFILE', 'staging'))
    p.add_argument('-y', '--yes', action='store_true', help='allow changes on prod')
    p.add_argument('-c', '--context', help='context JSON, e.g. {"lang": "en_US"}')
    sub = p.add_subparsers(dest='cmd', required=True)

    sub.add_parser('whoami')
    s = sub.add_parser('call', help='call any public method')
    s.add_argument('model'); s.add_argument('method')
    s.add_argument('--ids'); s.add_argument('--kw', help='keyword arguments as JSON (or @file.json)')
    s = sub.add_parser('search-read')
    s.add_argument('model'); s.add_argument('domain', nargs='?', default='[]')
    s.add_argument('--fields'); s.add_argument('--limit', type=int); s.add_argument('--offset', type=int)
    s.add_argument('--order')
    s = sub.add_parser('read'); s.add_argument('model'); s.add_argument('ids'); s.add_argument('--fields')
    s = sub.add_parser('count'); s.add_argument('model'); s.add_argument('domain', nargs='?', default='[]')
    s = sub.add_parser('create'); s.add_argument('model'); s.add_argument('values', help='JSON object or list, or @file.json')
    s = sub.add_parser('write'); s.add_argument('model'); s.add_argument('ids'); s.add_argument('values')
    s = sub.add_parser('unlink'); s.add_argument('model'); s.add_argument('ids')
    s = sub.add_parser('fields'); s.add_argument('model'); s.add_argument('--attrs', default='type,string,relation,required,readonly')
    s = sub.add_parser('attach', help='attach a file to a record')
    s.add_argument('model'); s.add_argument('id', type=int); s.add_argument('file')
    a = p.parse_args()

    try:
        odoo = Odoo(a.profile)
        ctx = parse_json(a.context, None)

        def run(model, method, ids=None, **kw):
            if odoo.profile == 'prod' and method not in READ_METHODS and not a.yes:
                raise OdooError(f'{model}.{method} may change prod data: rerun with --yes')
            return odoo.call(model, method, ids=ids, context=ctx, **kw)

        if a.cmd == 'whoami':
            ctx_info = odoo.call('res.users', 'context_get')
            me = odoo.call('res.users', 'read', ids=[ctx_info['uid']], fields=['name', 'login', 'company_id']) \
                if ctx_info.get('uid') else None
            res = {'profile': odoo.profile, 'url': odoo.url, 'db': odoo.db, 'context': ctx_info, 'user': me}
        elif a.cmd == 'call':
            res = run(a.model, a.method, ids=parse_ids(a.ids) if a.ids else None, **(parse_json(a.kw, {}) or {}))
        elif a.cmd == 'search-read':
            kw = {'domain': parse_json(a.domain, [])}
            if a.fields:
                kw['fields'] = a.fields.split(',')
            for k in ('limit', 'offset', 'order'):
                if getattr(a, k) is not None:
                    kw[k] = getattr(a, k)
            res = run(a.model, 'search_read', **kw)
        elif a.cmd == 'read':
            kw = {'fields': a.fields.split(',')} if a.fields else {}
            res = run(a.model, 'read', ids=parse_ids(a.ids), **kw)
        elif a.cmd == 'count':
            res = run(a.model, 'search_count', domain=parse_json(a.domain, []))
        elif a.cmd == 'create':
            vals = parse_json(a.values)
            res = run(a.model, 'create', vals_list=vals if isinstance(vals, list) else [vals])
        elif a.cmd == 'write':
            res = run(a.model, 'write', ids=parse_ids(a.ids), vals=parse_json(a.values))
        elif a.cmd == 'unlink':
            res = run(a.model, 'unlink', ids=parse_ids(a.ids))
        elif a.cmd == 'fields':
            res = run(a.model, 'fields_get', attributes=a.attrs.split(','))
        elif a.cmd == 'attach':
            with open(a.file, 'rb') as f:
                data = base64.b64encode(f.read()).decode()
            res = run('ir.attachment', 'create', vals_list=[{
                'name': os.path.basename(a.file), 'raw': data, 'res_model': a.model, 'res_id': a.id,
                'mimetype': mimetypes.guess_type(a.file)[0] or 'application/octet-stream',
            }])
    except OdooError as e:
        print(json.dumps({'error': str(e)}), file=sys.stderr)
        sys.exit(1)
    json.dump(res, sys.stdout, indent=2, ensure_ascii=False, default=str)
    print()


if __name__ == '__main__':
    main()
