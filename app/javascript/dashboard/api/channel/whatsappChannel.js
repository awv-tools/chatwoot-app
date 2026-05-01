/* global axios */
import ApiClient from '../ApiClient';

class WhatsappChannel extends ApiClient {
  constructor() {
    super('whatsapp', { accountScoped: true });
  }

  createEmbeddedSignup(params) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, params);
  }

  reauthorizeWhatsApp({ inboxId, ...params }) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, {
      ...params,
      inbox_id: inboxId,
    });
  }

  authorizeZernio({ inboxId, inboxName } = {}) {
    return axios.post(
      `/api/v2/accounts/${this.accountIdFromRoute}/zernio/authorize`,
      {
        inbox_id: inboxId,
        inbox_name: inboxName,
      }
    );
  }
}

export default new WhatsappChannel();
