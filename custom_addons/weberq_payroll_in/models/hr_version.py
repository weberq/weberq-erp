from odoo import fields, models


class HrVersion(models.Model):
    _inherit = 'hr.version'

    # Statutory schemes the employer is registered for, per employee: a small
    # company may not be covered by PF or ESI yet
    weberq_pf = fields.Boolean(
        string='Provident Fund', groups='hr.group_hr_user',
        help='Deduct the employee PF and book the employer PF on this contract.')
    weberq_esi = fields.Boolean(
        string='ESI', groups='hr.group_hr_user',
        help='Deduct the employee ESI and book the employer ESI while the gross is within the ESI wage limit.')
    weberq_pt = fields.Boolean(
        string='Professional Tax', default=True, groups='hr.group_hr_user',
        help='Deduct Telangana Professional Tax by its monthly slabs.')
