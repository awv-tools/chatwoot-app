import Auth from '../api/auth';
import { frontendURL } from './URLHelper';

const SUSPENDED_ACCOUNT_ERROR = 'Account is suspended';

// A hard redirect, not a router push: the cached user payload still reports the
// account as active, so the route guard would bounce us back to the dashboard.
const redirectToSuspendedScreen = error => {
  if (error?.response?.status !== 401) return;
  if (error.response.data?.error !== SUSPENDED_ACCOUNT_ERROR) return;

  const accountId = error.response.config?.url?.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;

  const suspendedURL = frontendURL(`accounts/${accountId}/suspended`);
  if (window.location.pathname === suspendedURL) return;

  window.location.assign(suspendedURL);
};

const parseErrorCode = error => {
  redirectToSuspendedScreen(error);
  return Promise.reject(error);
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => parseErrorCode(error)
  );
  return wootApi;
};
