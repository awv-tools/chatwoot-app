/* global axios */
import ApiClient from './ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getLabels(conversationID) {
    return axios.get(`${this.url}/${conversationID}/labels`);
  }

  updateLabels(conversationID, labels) {
    return axios.post(`${this.url}/${conversationID}/labels`, { labels });
  }

  markMessageReadOnProvider(conversationID) {
    return axios
      .post(`${this.url}/${conversationID}/mark_message_read_on_provider`)
      .catch(error => {
        return Promise.reject(error);
      });
  }
}

export default new ConversationApi();
