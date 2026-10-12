from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    weberq_pan = fields.Char(string='PAN', groups='hr.group_hr_user', size=10)
    weberq_uan = fields.Char(string='UAN', groups='hr.group_hr_user', help='Universal Account Number (Provident Fund)')
    weberq_esic_number = fields.Char(string='ESIC Number', groups='hr.group_hr_user')
