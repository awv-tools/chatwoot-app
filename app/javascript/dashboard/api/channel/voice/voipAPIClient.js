/* global axios */
import ApiClient from '../../ApiClient';

class VoipAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  accept({ inboxId, callSid }) {
    return axios
      .post(`${this.url}/${inboxId}/voip_calls/${callSid}/accept`)
      .then(r => r.data);
  }

  reject({ inboxId, callSid }) {
    return axios.post(`${this.url}/${inboxId}/voip_calls/${callSid}/reject`);
  }

  getCredentials(inboxId) {
    return axios
      .get(`${this.url}/${inboxId}/voip_calls/credentials`)
      .then(r => r.data);
  }
}

export default new VoipAPI();
