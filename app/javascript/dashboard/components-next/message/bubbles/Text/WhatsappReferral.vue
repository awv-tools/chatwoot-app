<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  referral: { type: Object, required: true },
});

const { t } = useI18n();
const hasMediaError = ref(false);

const safeUrl = value => {
  if (!value) return '';

  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : '';
  } catch {
    return '';
  }
};

const sourceUrl = computed(() => safeUrl(props.referral.sourceUrl));
const mediaUrl = computed(() =>
  safeUrl(
    props.referral.thumbnailUrl ||
      props.referral.imageUrl ||
      props.referral.mediaUrl ||
      props.referral.videoUrl
  )
);
const showMedia = computed(() => mediaUrl.value && !hasMediaError.value);
const isVideo = computed(
  () =>
    props.referral.mediaType === 'video' ||
    props.referral.mediaContentType?.startsWith('video/')
);
const renderVideo = computed(
  () => isVideo.value && !props.referral.thumbnailUrl
);
const label = computed(() =>
  props.referral.sourceType === 'post'
    ? t('CONVERSATION.REFERRAL.POST_LABEL')
    : t('CONVERSATION.REFERRAL.AD_LABEL')
);
const welcomeText = computed(() => props.referral.welcomeMessage?.text || '');

const handleMediaError = () => {
  hasMediaError.value = true;
};
</script>

<template>
  <div
    class="w-full max-w-md overflow-hidden border border-dashed rounded-xl rounded-bl-sm bg-n-alpha-1 border-n-amber-7"
    data-testid="whatsapp-referral"
  >
    <div
      class="flex items-center gap-2 px-3 py-2 border-b bg-n-amber-3 border-n-amber-7/40"
    >
      <Icon
        icon="i-lucide-megaphone"
        class="flex-shrink-0 size-4 text-n-amber-11"
      />
      <span class="text-xs font-medium text-n-amber-12">{{ label }}</span>
    </div>

    <component
      :is="sourceUrl ? 'a' : 'div'"
      v-if="showMedia"
      :href="sourceUrl || undefined"
      :target="sourceUrl ? '_blank' : undefined"
      :rel="sourceUrl ? 'noopener noreferrer' : undefined"
      class="relative block overflow-hidden bg-n-alpha-2 aspect-video"
    >
      <video
        v-if="renderVideo"
        :src="mediaUrl"
        muted
        preload="metadata"
        class="object-cover w-full h-full skip-context-menu"
        @error="handleMediaError"
      />
      <img
        v-else
        :src="mediaUrl"
        :alt="referral.headline || label"
        class="object-cover w-full h-full skip-context-menu"
        @error="handleMediaError"
      />
      <div
        v-if="isVideo"
        class="absolute inset-0 flex items-center justify-center pointer-events-none"
      >
        <div
          class="flex items-center justify-center rounded-full size-12 bg-n-alpha-black2"
        >
          <Icon icon="i-lucide-play" class="text-white size-6 ms-0.5" />
        </div>
      </div>
    </component>

    <div class="p-3 space-y-1.5">
      <h4
        v-if="referral.headline"
        class="mb-0 text-sm font-semibold leading-tight break-words text-n-slate-12"
      >
        {{ referral.headline }}
      </h4>
      <p
        v-if="referral.body"
        class="mb-0 text-sm leading-snug whitespace-pre-line break-words line-clamp-3 text-n-slate-11"
      >
        {{ referral.body }}
      </p>
      <a
        v-if="sourceUrl"
        :href="sourceUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 mt-1 text-xs font-medium text-n-amber-11 hover:text-n-amber-12 hover:underline"
      >
        <Icon icon="i-lucide-external-link" class="size-3" />
        {{ t('CONVERSATION.REFERRAL.VIEW_AD') }}
      </a>
    </div>

    <div
      v-if="welcomeText"
      class="px-3 pt-1 pb-3 text-xs border-t text-n-slate-10 border-n-amber-7/30"
    >
      <span class="font-medium text-n-slate-11">
        {{ t('CONVERSATION.REFERRAL.WELCOME_MESSAGE_LABEL') }}
      </span>
      <span class="italic">{{ welcomeText }}</span>
    </div>
  </div>
</template>
