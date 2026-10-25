/* global axios */
import ApiClient from '../../ApiClient';

// Cumpra AI WhatsApp calling. Call methods mirror whatsappCallsAPI.js so
// useWhatsappCallSession can use either one.
class WhatsappVoiceAPI extends ApiClient {
  constructor() {
    super('whatsapp_voice', { accountScoped: true });
  }

  enableCalling(inboxId) {
    return axios.post(`${this.url}/inboxes/${inboxId}/enable`);
  }

  disableCalling(inboxId) {
    return axios.post(`${this.url}/inboxes/${inboxId}/disable`);
  }

  // The Meta call id can hold characters that break a URL path, so it is sent as call_id
  show(callId) {
    return axios
      .get(`${this.url}/call`, { params: { call_id: callId } })
      .then(r => r.data);
  }

  accept(callId, sdpAnswer) {
    return axios
      .post(`${this.url}/call/accept`, {
        call_id: callId,
        sdp_answer: sdpAnswer,
      })
      .then(r => r.data);
  }

  reject(callId) {
    return axios
      .post(`${this.url}/call/reject`, { call_id: callId })
      .then(r => r.data);
  }

  terminate(callId) {
    return axios
      .post(`${this.url}/call/terminate`, { call_id: callId })
      .then(r => r.data);
  }
}

export default new WhatsappVoiceAPI();
