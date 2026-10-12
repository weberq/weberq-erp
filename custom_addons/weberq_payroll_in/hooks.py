# Accounts of the salary rules, by account of the Indian chart of accounts:
# rule: (debit account, credit account). Deductions are negative amounts, so
# their liability goes on the debit side, which credits it.
RULE_ACCOUNTS = {
    'rule_basic': ('p2101', None),              # Salary Expense
    'rule_hra': ('p2101', None),
    'rule_special': ('p2101', None),
    'rule_bonus': ('p2101', None),
    'rule_pf_employee': ('p300007', None),      # Provident fund - Employee Payable
    'rule_esi_employee': ('p300014', None),     # ESIC - Employee Payable
    'rule_professional_tax': ('p300012', None),  # Professional Tax Payable
    'rule_tds': ('p300019', None),              # TDS - Employee Payable
    'rule_net': (None, 'p300010'),              # Salary Exp Payable
    'rule_pf_employer': ('p2101', 'p300008'),   # Provident fund - Employer Payable
    'rule_esi_employer': ('p2101', 'p300015'),  # ESIC - Employer Payable
}


def post_init_hook(env):
    for company in env['res.company'].search([('chart_template', '=', 'in')]):
        setup_company_accounting(env, company)


def setup_company_accounting(env, company):
    """ Set the accounts of the salary rules and the salary journal of `company`. """
    def account(code):
        return env.ref(f'account.{company.id}_{code}', raise_if_not_found=False)

    for xmlid, (debit, credit) in RULE_ACCOUNTS.items():
        rule = env.ref(f'weberq_payroll_in.{xmlid}').with_company(company)
        vals = {}
        if debit and account(debit):
            vals['account_debit'] = account(debit).id
        if credit and account(credit):
            vals['account_credit'] = account(credit).id
        rule.write(vals)

    journal = env['account.journal'].search([('code', '=', 'SAL'), ('company_id', '=', company.id)], limit=1)
    if not journal:
        journal = env['account.journal'].create({
            'name': 'Salaries', 'code': 'SAL', 'type': 'general', 'company_id': company.id,
        })
    env['ir.default'].set('hr.version', 'journal_id', journal.id, company_id=company.id)
    env['hr.version'].search([('company_id', '=', company.id), ('journal_id', '=', False)]).journal_id = journal
