<script setup>
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { onMounted } from 'vue';

const SUPPORT_WHATSAPP_URL = 'https://wa.me/5581989112212';

const toggleSupportWidgetVisibility = () => {
  if (window.$chatwoot) {
    window.$chatwoot.toggleBubbleVisibility('show');
  }
};

const openSupportWhatsApp = () => {
  window.open(SUPPORT_WHATSAPP_URL, '_blank', 'noopener');
};

const setupListenerForWidgetEvent = () => {
  window.addEventListener('chatwoot:on-message', () => {
    toggleSupportWidgetVisibility();
  });
};

onMounted(() => {
  toggleSupportWidgetVisibility();
  setupListenerForWidgetEvent();
});
</script>

<template>
  <div class="items-center bg-n-slate-2 flex justify-center h-full w-full">
    <EmptyState
      :title="$t('APP_GLOBAL.ACCOUNT_SUSPENDED.TITLE')"
      :message="$t('APP_GLOBAL.ACCOUNT_SUSPENDED.MESSAGE')"
    >
      <div class="flex justify-center">
        <NextButton
          icon="i-lucide-message-circle"
          :label="$t('SIDEBAR_ITEMS.CONTACT_SUPPORT')"
          @click="openSupportWhatsApp"
        />
      </div>
    </EmptyState>
  </div>
</template>
