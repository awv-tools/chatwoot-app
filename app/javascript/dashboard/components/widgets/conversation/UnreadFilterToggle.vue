<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const isActive = computed({
  get: () => props.modelValue,
  set: value => emit('update:modelValue', value),
});

const toggle = () => {
  isActive.value = !isActive.value;
};
</script>

<template>
  <NextButton
    v-tooltip.top-end="
      isActive
        ? t('CHAT_LIST.SHOW_ALL_CONVERSATIONS')
        : t('CHAT_LIST.SHOW_UNREAD_ONLY')
    "
    :icon="
      isActive ? 'i-lucide-message-square-dot' : 'i-lucide-message-square-dot'
    "
    :color="isActive ? 'blue' : 'slate'"
    :variant="isActive ? 'solid' : 'faded'"
    xs
    @click="toggle"
  />
</template>
