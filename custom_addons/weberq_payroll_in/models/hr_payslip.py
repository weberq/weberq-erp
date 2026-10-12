from odoo import api, models


class HrPayslip(models.Model):
    _inherit = 'hr.payslip'

    @api.model_create_multi
    def create(self, vals_list):
        # Payslip batches and imports don't run the onchange that picks the
        # journal of the contract: without this, the first general journal of
        # the company (Miscellaneous Operations) would book the salaries
        for vals in vals_list:
            if vals.get('journal_id') or self.env.context.get('journal_id'):
                continue
            journal = self.env['hr.version'].browse(vals.get('version_id')).journal_id
            if not journal:
                company_id = vals.get('company_id') or self.env.company.id
                journal = self.env['account.journal'].sudo().search(
                    [('code', '=', 'SAL'), ('type', '=', 'general'), ('company_id', '=', company_id)], limit=1)
            if journal:
                vals['journal_id'] = journal.id
        return super().create(vals_list)
