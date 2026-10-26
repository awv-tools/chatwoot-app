<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required, requiredIf } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import {
  BRAZIL_DIAL_CODE,
  useBrazilianPhoneNumber,
} from 'dashboard/composables/useBrazilianPhoneNumber';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import PageHeader from '../../SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

// Brazilian numbers only for now: the agent types the area code and number
const {
  digits: phoneNumber,
  formatted: formattedPhoneNumber,
  e164: phoneNumberE164,
  isValid: isValidPhoneNumber,
  onInput: onPhoneNumberInput,
} = useBrazilianPhoneNumber();

const state = reactive({
  channelName: '',
  phoneNumber,
  sipServer: '',
  sipPort: '5060',
  sipUsername: '',
  sipPassword: '',
  aiEnabled: false,
});

// The operator's SIP account is optional, but all or nothing
const hasSipAccount = computed(() =>
  [state.sipServer, state.sipUsername, state.sipPassword].some(Boolean)
);

const uiFlags = useMapGetter('inboxes/getUIFlags');

const requiredForSip = { required: requiredIf(hasSipAccount) };
const v$ = useVuelidate(
  {
    channelName: { required },
    phoneNumber: {
      validNumber: () => isValidPhoneNumber.value,
    },
    sipServer: requiredForSip,
    sipPort: requiredForSip,
    sipUsername: requiredForSip,
    sipPassword: requiredForSip,
  },
  state
);
const isSubmitDisabled = computed(() => v$.value.$invalid);

const formErrors = computed(() => ({
  channelName: v$.value.channelName.$error
    ? t('INBOX_MGMT.ADD.VOIP.CHANNEL_NAME.ERROR')
    : '',
  phoneNumber: v$.value.phoneNumber.$error
    ? t('INBOX_MGMT.ADD.VOIP.PHONE_NUMBER.ERROR')
    : '',
  sipServer: v$.value.sipServer.$error
    ? t('INBOX_MGMT.ADD.VOIP.SIP.ERROR')
    : '',
  sipPort: v$.value.sipPort.$error ? t('INBOX_MGMT.ADD.VOIP.SIP.ERROR') : '',
  sipUsername: v$.value.sipUsername.$error
    ? t('INBOX_MGMT.ADD.VOIP.SIP.ERROR')
    : '',
  sipPassword: v$.value.sipPassword.$error
    ? t('INBOX_MGMT.ADD.VOIP.SIP.ERROR')
    : '',
}));

async function createChannel() {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: state.channelName,
      channel: {
        type: 'voip',
        phone_number: phoneNumberE164.value,
        ai_enabled: state.aiEnabled,
        ...(hasSipAccount.value && {
          sip_server: state.sipServer,
          sip_port: Number(state.sipPort),
          sip_username: state.sipUsername,
          sip_password: state.sipPassword,
        }),
      },
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: inbox.id },
    });
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.VOIP.API.ERROR_MESSAGE'));
  }
}
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.VOIP.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.VOIP.DESC')"
    />

    <form
      class="flex flex-col gap-4 flex-wrap mx-0"
      @submit.prevent="createChannel"
    >
      <Input
        v-model="state.channelName"
        :label="t('INBOX_MGMT.ADD.VOIP.CHANNEL_NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.VOIP.CHANNEL_NAME.PLACEHOLDER')"
        :message="formErrors.channelName"
        :message-type="formErrors.channelName ? 'error' : 'info'"
        @blur="v$.channelName.$touch"
      />

      <div class="flex flex-col gap-1">
        <label
          for="voip-phone-number"
          class="mb-0.5 text-heading-3 text-n-slate-12"
        >
          {{ t('INBOX_MGMT.ADD.VOIP.PHONE_NUMBER.LABEL') }}
        </label>
        <Input
          id="voip-phone-number"
          :model-value="formattedPhoneNumber"
          type="tel"
          inputmode="numeric"
          custom-input-class="!ps-12"
          :placeholder="t('INBOX_MGMT.ADD.VOIP.PHONE_NUMBER.PLACEHOLDER')"
          :message="
            formErrors.phoneNumber || t('INBOX_MGMT.ADD.VOIP.PHONE_NUMBER.HELP')
          "
          :message-type="formErrors.phoneNumber ? 'error' : 'info'"
          @input="onPhoneNumberInput"
          @blur="v$.phoneNumber.$touch"
        >
          <template #prefix>
            <span
              class="absolute top-0 flex items-center h-10 pointer-events-none start-3 text-sm text-n-slate-11"
            >
              {{ BRAZIL_DIAL_CODE }}
            </span>
          </template>
        </Input>
      </div>

      <div class="flex flex-col gap-1">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.VOIP.SIP.TITLE') }}
        </h3>
        <p class="text-body-main text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.VOIP.SIP.DESC') }}
        </p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Input
          v-model="state.sipServer"
          class="sm:col-span-2"
          :label="t('INBOX_MGMT.ADD.VOIP.SIP.SERVER.LABEL')"
          :placeholder="t('INBOX_MGMT.ADD.VOIP.SIP.SERVER.PLACEHOLDER')"
          :message="formErrors.sipServer"
          :message-type="formErrors.sipServer ? 'error' : 'info'"
          @blur="v$.sipServer.$touch"
        />
        <Input
          v-model="state.sipPort"
          type="number"
          min="1"
          max="65535"
          :label="t('INBOX_MGMT.ADD.VOIP.SIP.PORT.LABEL')"
          :message="formErrors.sipPort"
          :message-type="formErrors.sipPort ? 'error' : 'info'"
          @blur="v$.sipPort.$touch"
        />
      </div>

      <Input
        v-model="state.sipUsername"
        :label="t('INBOX_MGMT.ADD.VOIP.SIP.USERNAME.LABEL')"
        :message="formErrors.sipUsername"
        :message-type="formErrors.sipUsername ? 'error' : 'info'"
        @blur="v$.sipUsername.$touch"
      />

      <Input
        v-model="state.sipPassword"
        type="password"
        :label="t('INBOX_MGMT.ADD.VOIP.SIP.PASSWORD.LABEL')"
        :message="
          formErrors.sipPassword || t('INBOX_MGMT.ADD.VOIP.SIP.PASSWORD.HELP')
        "
        :message-type="formErrors.sipPassword ? 'error' : 'info'"
        @blur="v$.sipPassword.$touch"
      />

      <SettingsToggleSection
        v-model="state.aiEnabled"
        :header="t('INBOX_MGMT.ADD.VOIP.AI.TITLE')"
        :description="t('INBOX_MGMT.ADD.VOIP.AI.DESC')"
      />

      <div>
        <NextButton
          :is-loading="uiFlags.isCreating"
          :disabled="isSubmitDisabled"
          :label="t('INBOX_MGMT.ADD.VOIP.SUBMIT_BUTTON')"
          type="submit"
        />
      </div>
    </form>
  </div>
</template>
