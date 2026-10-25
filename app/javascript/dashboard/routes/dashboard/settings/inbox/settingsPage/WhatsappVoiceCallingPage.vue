<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappVoiceAPI from 'dashboard/api/channel/whatsapp/whatsappVoiceAPI';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const store = useStore();
const { t } = useI18n();

const callingEnabled = ref(!!props.inbox.provider_config?.calling_enabled);
const isToggling = ref(false);

const phoneNumber = computed(
  () => props.inbox.provider_config?.phone_number || props.inbox.phone_number
);

watch(
  () => props.inbox.provider_config?.calling_enabled,
  value => {
    callingEnabled.value = !!value;
  }
);

const handleCallingToggle = async enabled => {
  if (isToggling.value) return;
  const previousValue = callingEnabled.value;
  callingEnabled.value = enabled;
  isToggling.value = true;
  try {
    if (enabled) {
      await WhatsappVoiceAPI.enableCalling(props.inbox.id);
    } else {
      await WhatsappVoiceAPI.disableCalling(props.inbox.id);
    }
    await store.dispatch('inboxes/get', props.inbox.id);
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (_) {
    callingEnabled.value = previousValue;
    useAlert(
      enabled
        ? t('INBOX_MGMT.WHATSAPP_CALLING.ENABLE_FAILED')
        : t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
    );
  } finally {
    isToggling.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div
      class="relative"
      :class="{ 'pointer-events-none opacity-60': isToggling }"
    >
      <SettingsToggleSection
        :model-value="callingEnabled"
        :header="t('INBOX_MGMT.WHATSAPP_CALLING.ENABLE.LABEL')"
        :description="t('INBOX_MGMT.WHATSAPP_CALLING.ENABLE.DESCRIPTION')"
        :hide-toggle="isToggling"
        @update:model-value="handleCallingToggle"
      >
        <template v-if="isToggling" #hiddenToggle>
          <Spinner class="size-4 text-n-slate-11" />
        </template>
      </SettingsToggleSection>
    </div>

    <template v-if="callingEnabled">
      <SettingsFieldSection
        v-if="phoneNumber"
        :label="t('INBOX_MGMT.WHATSAPP_CALLING.PHONE_NUMBER.LABEL')"
        :help-text="t('INBOX_MGMT.WHATSAPP_CALLING.PHONE_NUMBER.HELP_TEXT')"
      >
        <woot-code :script="phoneNumber" lang="html" />
      </SettingsFieldSection>

      <SettingsFieldSection
        :label="t('INBOX_MGMT.WHATSAPP_CALLING.HOW_IT_WORKS.LABEL')"
        :help-text="t('INBOX_MGMT.WHATSAPP_CALLING.HOW_IT_WORKS.DESCRIPTION')"
      />
    </template>
  </div>
</template>
