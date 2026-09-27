<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  buttons: {
    type: Array,
    required: true,
  },
});

const BUTTON_ICONS = {
  URL: 'i-lucide-external-link',
  PHONE_NUMBER: 'i-lucide-phone',
  COPY_CODE: 'i-lucide-copy',
};
const DEFAULT_BUTTON_ICON = 'i-lucide-reply';
</script>

<template>
  <div class="flex flex-col gap-2">
    <Button
      v-for="(button, index) in buttons"
      :key="index"
      :label="button.text"
      :icon="BUTTON_ICONS[button.type] || DEFAULT_BUTTON_ICON"
      :title="button.url || button.phoneNumber"
      slate
      faded
      sm
      disabled
      class="w-full"
    />
  </div>
</template>
