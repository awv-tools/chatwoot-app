<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import InboxReconnectionRequired from '../../components/InboxReconnectionRequired.vue';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const isRequestingAuthorization = ref(false);

const requestAuthorization = async () => {
  isRequestingAuthorization.value = true;
  try {
    const response = await WhatsappChannel.authorizeZernio({
      inboxId: props.inbox.id,
    });
    const authUrl = response?.data?.authUrl;
    if (!authUrl) {
      throw new Error(t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'));
    }
    window.location.href = authUrl;
  } catch (error) {
    isRequestingAuthorization.value = false;
    useAlert(
      parseAPIErrorResponse(error) ||
        error.message ||
        t('INBOX.REAUTHORIZE.ERROR')
    );
  }
};

defineExpose({ requestAuthorization });
</script>

<template>
  <InboxReconnectionRequired
    class="mx-6"
    :is-loading="isRequestingAuthorization"
    @reauthorize="requestAuthorization"
  />
</template>
