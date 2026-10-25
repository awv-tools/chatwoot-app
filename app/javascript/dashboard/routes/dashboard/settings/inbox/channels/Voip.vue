<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import PageHeader from '../../SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

// The number is either an E.164 phone number or, in development, a test extension such as 1000
const state = reactive({ channelName: '', phoneNumber: '' });

const uiFlags = useMapGetter('inboxes/getUIFlags');

const v$ = useVuelidate(
  { channelName: { required }, phoneNumber: { required } },
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
}));

async function createChannel() {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: state.channelName,
      channel: { type: 'voip', phone_number: state.phoneNumber },
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

      <Input
        v-model="state.phoneNumber"
        :label="t('INBOX_MGMT.ADD.VOIP.PHONE_NUMBER.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.VOIP.PHONE_NUMBER.PLACEHOLDER')"
        :message="
          formErrors.phoneNumber || t('INBOX_MGMT.ADD.VOIP.PHONE_NUMBER.HELP')
        "
        :message-type="formErrors.phoneNumber ? 'error' : 'info'"
        @blur="v$.phoneNumber.$touch"
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
