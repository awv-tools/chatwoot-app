<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SpinnerLoader from 'dashboard/components-next/spinner/Spinner.vue';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const phones = ref([]);
const isLoading = ref(true);
const isSubmitting = ref(false);
const filter = ref('');

const filteredPhones = computed(() => {
  const term = filter.value.replace(/\D/g, '');
  if (!term) return phones.value;
  return phones.value.filter(p => {
    const digits = (p.display_phone_number || '').replace(/\D/g, '');
    return digits.includes(term);
  });
});

onMounted(async () => {
  try {
    const { data } = await WhatsappChannel.fetchZernioSelectPhoneData(
      route.params.state
    );
    phones.value = data.phones || [];
  } catch (error) {
    useAlert(
      error.message || t('INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.ERROR')
    );
    router.push(`/app/accounts/${route.params.accountId}/dashboard`);
  } finally {
    isLoading.value = false;
  }
});

const select = async phone => {
  if (isSubmitting.value) return;
  isSubmitting.value = true;
  try {
    const { data } = await WhatsappChannel.submitZernioSelectPhone({
      state: route.params.state,
      phoneNumberId: phone.id,
      wabaId: phone.wabaId,
    });
    if (data.redirect_path) {
      router.push(data.redirect_path);
    }
  } catch (error) {
    useAlert(
      error.message || t('INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.ERROR')
    );
    isSubmitting.value = false;
  }
};

const cancel = () => {
  router.push(`/app/accounts/${route.params.accountId}/dashboard`);
};

const qualityColor = quality => {
  switch (quality) {
    case 'GREEN':
      return 'text-n-teal-11';
    case 'YELLOW':
      return 'text-n-amber-11';
    case 'RED':
      return 'text-n-ruby-11';
    default:
      return 'text-n-slate-10';
  }
};

const qualityLabel = quality => {
  if (!quality) return '—';
  const key = `INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.QUALITY.${quality}`;
  const translated = t(key);
  // Se a key não existe (i18n retorna a própria key), cai pro raw
  return translated === key ? quality : translated;
};
</script>

<template>
  <div class="min-h-screen p-6 flex justify-center bg-n-background">
    <div class="w-full max-w-2xl">
      <h2 class="text-xl font-semibold text-n-slate-12 mb-2">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11 mb-6">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.DESC') }}
      </p>

      <div v-if="isLoading" class="flex justify-center py-12">
        <SpinnerLoader />
      </div>

      <template v-else>
        <input
          v-model="filter"
          type="tel"
          inputmode="numeric"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.FILTER_PLACEHOLDER')
          "
          class="block w-full rounded-lg border border-n-strong px-3 py-2 text-sm bg-n-alpha-1 text-n-slate-12 mb-4"
        />

        <div
          v-if="filteredPhones.length === 0"
          class="text-center py-8 text-n-slate-10 text-sm"
        >
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.EMPTY') }}
        </div>

        <div class="flex flex-col gap-2">
          <button
            v-for="phone in filteredPhones"
            :key="phone.id"
            type="button"
            :disabled="isSubmitting"
            class="text-left rounded-lg border border-n-weak hover:border-n-brand p-4 bg-n-alpha-1 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            @click="select(phone)"
          >
            <div class="flex justify-between items-start gap-4">
              <div class="flex-1">
                <div class="text-base font-medium text-n-slate-12">
                  {{ phone.verified_name || phone.display_phone_number }}
                </div>
                <div class="text-sm text-n-slate-11 mt-0.5">
                  {{ phone.display_phone_number }}
                </div>
                <div v-if="phone.wabaName" class="text-xs text-n-slate-10 mt-1">
                  {{ phone.wabaName }}
                </div>
              </div>
              <div
                class="text-xs font-medium text-right"
                :class="qualityColor(phone.quality_rating)"
              >
                <div class="text-n-slate-10 font-normal mb-0.5">
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.QUALITY_LABEL'
                    )
                  }}
                </div>
                {{ qualityLabel(phone.quality_rating) }}
              </div>
            </div>
          </button>
        </div>

        <div class="flex justify-end gap-2 mt-6">
          <NextButton
            faded
            slate
            :disabled="isSubmitting"
            :label="$t('INBOX_MGMT.ADD.WHATSAPP.ZERNIO.SELECT_PHONE.CANCEL')"
            @click="cancel"
          />
        </div>
      </template>
    </div>
  </div>
</template>
