{
    'name': 'WeberQ Payroll India',
    'version': '20.0.1.0.0',
    'category': 'Human Resources/Payroll',
    'summary': 'Indian salary structure: Basic, HRA, PF, ESI, Telangana PT, TDS',
    'description': """
Monthly salary structure for WeberQ Global, on top of the Odoomates payroll:

* Earnings: Basic, HRA and Special Allowance from the monthly gross on the
  contract, prorated for unpaid leave, plus Bonus / Arrears as a payslip input.
* Deductions: Provident Fund, ESI, Telangana Professional Tax and TDS
  (entered per payslip from the employee's tax projection).
* Employer contributions: Provident Fund and ESI.
* Rates, ceilings and slabs are rule parameters and salary brackets, dated,
  so a change in the law is a new value rather than a code change.
* Payslips post to the Indian chart of accounts, through a Salary journal.
""",
    'author': 'Pranay Kiran',
    'website': 'https://weberq.in',
    'license': 'LGPL-3',
    'depends': ['om_hr_payroll_account', 'l10n_in'],
    'data': [
        'data/payroll_parameters.xml',
        'data/payroll_structure.xml',
        'views/hr_views.xml',
    ],
    'post_init_hook': 'post_init_hook',
    'installable': True,
    'application': False,
}
