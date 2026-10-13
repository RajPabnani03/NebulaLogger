import { api } from 'lwc';
import LightningDatatable from '@salesforce/sfdx-lwc-jest/src/lightning-stubs/datatable/datatable';

export default class Datatable extends LightningDatatable {
  @api wrapTableHeader;
}
