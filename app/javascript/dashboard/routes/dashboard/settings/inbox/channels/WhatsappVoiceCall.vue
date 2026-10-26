<script setup>
import { computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { isPhoneE164OrEmpty, isNumber } from 'shared/helpers/Validators';
import WhatsappVoiceAPI from 'dashboard/api/channel/whatsapp/whatsappVoiceAPI';
import NextButton from 'dashboard/components-next/button/Button.vue';

// Our own WhatsApp Cloud inbox form: creates the inbox, then turns on Cumpra AI calling (WhatsappVoice)
const { t } = useI18n();
const store = useStore();
const router = useRouter();
const uiFlags = useMapGetter('inboxes/getUIFlags');

const state = reactive({
  inboxName: '',
  phoneNumber: '',
  apiKey: '',
  phoneNumberId: '',
  businessAccountId: '',
});

const v$ = useVuelidate(
  {
    inboxName: { required },
    phoneNumber: { required, isPhoneE164OrEmpty },
    apiKey: { required },
    phoneNumberId: { required, isNumber },
    businessAccountId: { required, isNumber },
  },
  state
);

const fields = computed(() => [
  {
    key: 'inboxName',
    label: t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL'),
    placeholder: t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER'),
    error: t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR'),
  },
  {
    key: 'phoneNumber',
    label: t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL'),
    placeholder: t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER'),
    error: t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR'),
  },
  {
    key: 'phoneNumberId',
    label: t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.LABEL'),
    placeholder: t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.PLACEHOLDER'),
    error: t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.ERROR'),
  },
  {
    key: 'businessAccountId',
    label: t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.LABEL'),
    placeholder: t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.PLACEHOLDER'),
    error: t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.ERROR'),
  },
  {
    key: 'apiKey',
    label: t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.LABEL'),
    placeholder: t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.PLACEHOLDER'),
    error: t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.ERROR'),
  },
]);

const createChannel = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: state.inboxName.trim(),
      channel: {
        type: 'whatsapp',
        phone_number: state.phoneNumber,
        provider: 'whatsapp_cloud',
        provider_config: {
          api_key: state.apiKey,
          phone_number_id: state.phoneNumberId,
          business_account_id: state.businessAccountId,
        },
      },
    });

    try {
      await WhatsappVoiceAPI.enableCalling(inbox.id);
    } catch (_) {
      useAlert(t('INBOX_MGMT.WHATSAPP_CALLING.ENABLE_FAILED'));
    }

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: inbox.id },
    });
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <div class="px-6 py-5 rounded-2xl border border-n-weak">
      <form
        class="flex flex-wrap flex-col mx-0"
        @submit.prevent="createChannel"
      >
        <div
          v-for="field in fields"
          :key="field.key"
          class="flex-shrink-0 flex-grow-0"
        >
          <label :class="{ error: v$[field.key].$error }">
            {{ field.label }}
            <input
              v-model="state[field.key]"
              type="text"
              :placeholder="field.placeholder"
              @blur="v$[field.key].$touch"
            />
            <span v-if="v$[field.key].$error" class="message">
              {{ field.error }}
            </span>
          </label>
        </div>

        <div class="w-full mt-4">
          <NextButton
            :disabled="uiFlags.isCreating"
            :is-loading="uiFlags.isCreating"
            type="submit"
            solid
            blue
            :label="t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
          />
        </div>
      </form>
    </div>
  </div>
</template>
