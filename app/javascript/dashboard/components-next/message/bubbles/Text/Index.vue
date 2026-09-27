<script setup>
import { computed, ref } from 'vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import TemplateButtons from './TemplateButtons.vue';
import { MESSAGE_TYPES } from '../../constants';
import { MESSAGE_STATUS } from 'shared/constants/messages';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const { content, attachments, contentAttributes, messageType, status } =
  useMessageContext();

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const renderOriginal = ref(false);

const renderContent = computed(() => {
  if (renderOriginal.value) {
    return content.value;
  }

  if (hasTranslations.value) {
    return translationContent.value;
  }

  return content.value;
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const template = computed(() => contentAttributes.value?.template);

const contactInfoRequestState = computed(() => {
  if (status.value === MESSAGE_STATUS.FAILED) return null;

  return contentAttributes.value?.whatsappContactInfo?.state;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span v-if="isEmpty" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <template v-if="template?.header">
        <span
          v-if="template.header.format === 'TEXT'"
          class="font-semibold text-n-slate-12"
        >
          {{ template.header.text }}
        </span>
        <img
          v-else-if="
            template.header.format === 'IMAGE' && template.header.mediaUrl
          "
          :src="template.header.mediaUrl"
          :alt="template.header.mediaName"
          class="max-h-64 rounded-lg object-cover"
        />
        <video
          v-else-if="
            template.header.format === 'VIDEO' && template.header.mediaUrl
          "
          :src="template.header.mediaUrl"
          controls
          class="max-h-64 rounded-lg"
        />
        <a
          v-else-if="
            template.header.format === 'DOCUMENT' && template.header.mediaUrl
          "
          :href="template.header.mediaUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center gap-2 px-3 py-2 rounded-lg bg-n-alpha-2 text-sm text-n-slate-12"
        >
          <span class="i-lucide-file-text size-4 shrink-0" />
          <span class="truncate">{{ template.header.mediaName }}</span>
        </a>
      </template>
      <FormattedContent v-if="renderContent" :content="renderContent" />
      <span v-if="template?.footer" class="text-xs text-n-slate-11">
        {{ template.footer }}
      </span>
      <TemplateButtons
        v-if="template?.buttons?.length"
        :buttons="template.buttons"
      />
      <span
        v-if="contactInfoRequestState === 'pending'"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ $t('CONVERSATION.REQUEST_CONTACT_INFO.STATES.PENDING') }}
      </span>
      <span
        v-else-if="contactInfoRequestState === 'shared'"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ $t('CONVERSATION.REQUEST_CONTACT_INFO.STATES.SHARED') }}
      </span>
      <span
        v-else-if="contactInfoRequestState === 'identity_conflict'"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ $t('CONVERSATION.REQUEST_CONTACT_INFO.STATES.IDENTITY_CONFLICT') }}
      </span>
      <TranslationToggle
        v-if="hasTranslations"
        class="-mt-3"
        :showing-original="renderOriginal"
        @toggle="handleSeeOriginal"
      />
      <AttachmentChips :attachments="attachments" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
