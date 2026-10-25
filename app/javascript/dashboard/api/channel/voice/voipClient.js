import VoipAPI from './voipAPIClient';

const createCallDisconnectedEvent = () => new CustomEvent('call:disconnected');

// Agent softphone for Channel::Voip inboxes: SIP over WebSocket + WebRTC to the
// voice platform. Same surface as TwilioVoiceClient so useCallSession can swap them.
class VoipClient extends EventTarget {
  constructor() {
    super();
    this.simpleUser = null;
  }

  async initializeDevice(inboxId) {
    this.destroyDevice();

    const credentials = await VoipAPI.getCredentials(inboxId);
    // Loaded on first use so sip.js stays out of the main dashboard bundle
    const { Web } = await import('sip.js');

    this.simpleUser = new Web.SimpleUser(credentials.wss_url, {
      aor: credentials.sip_uri,
      media: {
        constraints: { audio: true, video: false },
        remote: { audio: new Audio() },
      },
      userAgentOptions: {
        authorizationUsername: credentials.username,
        authorizationPassword: credentials.password,
        sessionDescriptionHandlerFactoryOptions: {
          peerConnectionConfiguration: { iceServers: credentials.ice_servers },
        },
      },
      delegate: { onCallHangup: this.onDisconnect },
    });
    await this.simpleUser.connect();

    return this.simpleUser;
  }

  setMuted(shouldMute) {
    if (!this.simpleUser) return false;
    if (shouldMute) {
      this.simpleUser.mute();
    } else {
      this.simpleUser.unmute();
    }
    return shouldMute;
  }

  async joinClientCall({ to }) {
    if (!this.simpleUser || !to) return null;
    await this.simpleUser.call(to);
    return this.simpleUser;
  }

  // Sends BYE, or CANCEL while still connecting; rejects when there is no call, which is a no-op here
  endClientCall() {
    this.simpleUser?.hangup().catch(() => {});
  }

  destroyDevice() {
    this.simpleUser?.disconnect().catch(() => {});
    this.simpleUser = null;
  }

  onDisconnect = () => {
    this.dispatchEvent(createCallDisconnectedEvent());
  };
}

export default new VoipClient();
