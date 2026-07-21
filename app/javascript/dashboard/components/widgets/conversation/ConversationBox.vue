<script>
import { mapGetters } from 'vuex';
import ConversationHeader from './ConversationHeader.vue';
import DashboardAppFrame from '../DashboardApp/Frame.vue';
import EmptyState from './EmptyState/EmptyState.vue';
import MessagesView from './MessagesView.vue';
import ConversationApi from 'dashboard/api/conversations';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export default {
  components: {
    ConversationHeader,
    DashboardAppFrame,
    EmptyState,
    MessagesView,
  },
  props: {
    inboxId: {
      type: [Number, String],
      default: '',
      required: false,
    },
    isInboxView: {
      type: Boolean,
      default: false,
    },
    isContactPanelOpen: {
      type: Boolean,
      default: true,
    },
    isOnExpandedLayout: {
      type: Boolean,
      default: true,
    },
  },
  data() {
    return { activeIndex: 0 };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      dashboardApps: 'dashboardApps/getRecords',
    }),
    inbox() {
      if (!this.currentChat.inbox_id) return null;
      return this.$store.getters['inboxes/getInbox'](this.currentChat.inbox_id);
    },
    isWhatsAppChannel() {
      return this.inbox?.channel_type === INBOX_TYPES.WHATSAPP;
    },
    // Null until the inbox is loaded, so the read receipt waits for channel_type
    whatsAppConversationId() {
      return this.isWhatsAppChannel ? this.currentChat.id : null;
    },
    dashboardAppTabs() {
      return [
        {
          key: 'messages',
          index: 0,
          name: this.$t('CONVERSATION.DASHBOARD_APP_TAB_MESSAGES'),
        },
        ...this.dashboardApps.map((dashboardApp, index) => ({
          key: `dashboard-${dashboardApp.id}`,
          index: index + 1,
          name: dashboardApp.title,
        })),
      ];
    },
    showContactPanel() {
      return this.isContactPanelOpen && this.currentChat.id;
    },
  },
  watch: {
    'currentChat.inbox_id': {
      immediate: true,
      handler(inboxId) {
        if (inboxId) {
          this.$store.dispatch('inboxAssignableAgents/fetch', {
            inboxIds: [inboxId],
            includeAgentBots: true,
          });
        }
      },
    },
    'currentChat.id'() {
      this.fetchLabels();
      this.activeIndex = 0;
    },
    whatsAppConversationId: {
      immediate: true,
      handler(conversationId) {
        if (conversationId) {
          ConversationApi.markMessageReadOnProvider(conversationId);
        }
      },
    },
  },
  mounted() {
    this.fetchLabels();
    this.$store.dispatch('dashboardApps/get');
  },
  methods: {
    fetchLabels() {
      if (!this.currentChat.id) {
        return;
      }
      this.$store.dispatch('conversationLabels/get', this.currentChat.id);
    },
    onDashboardAppTabChange(index) {
      this.activeIndex = index;
    },
  },
};
</script>

<template>
  <div
    class="conversation-details-wrap flex flex-col min-w-0 w-full bg-n-surface-1 relative"
    :class="{
      'border-l rtl:border-l-0 rtl:border-r border-n-weak': !isOnExpandedLayout,
    }"
  >
    <ConversationHeader
      v-if="currentChat.id"
      :chat="currentChat"
      :show-back-button="isOnExpandedLayout && !isInboxView"
      :class="{
        'border-b border-b-n-weak !pt-2': !dashboardApps.length,
      }"
    />
    <woot-tabs
      v-if="dashboardApps.length && currentChat.id"
      :index="activeIndex"
      class="h-10"
      @change="onDashboardAppTabChange"
    >
      <woot-tabs-item
        v-for="tab in dashboardAppTabs"
        :key="tab.key"
        :index="tab.index"
        :name="tab.name"
        :show-badge="false"
        is-compact
      />
    </woot-tabs>
    <div v-show="!activeIndex" class="flex h-full min-h-0 m-0">
      <MessagesView
        v-if="currentChat.id"
        :inbox-id="inboxId"
        :is-inbox-view="isInboxView"
      />
      <EmptyState
        v-if="!currentChat.id && !isInboxView"
        :is-on-expanded-layout="isOnExpandedLayout"
      />
      <slot />
    </div>
    <DashboardAppFrame
      v-for="(dashboardApp, index) in dashboardApps"
      v-show="activeIndex - 1 === index"
      :key="currentChat.id + '-' + dashboardApp.id"
      :is-visible="activeIndex - 1 === index"
      :config="dashboardApps[index].content"
      :position="index"
      :current-chat="currentChat"
    />
  </div>
</template>
