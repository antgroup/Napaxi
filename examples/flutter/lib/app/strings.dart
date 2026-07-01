part of '../main.dart';

class AppStrings {
  const AppStrings({
    required this.appTitle,
    required this.welcomeMessage,
    required this.welcomeReadyMessage,
    required this.noModelConfigured,
    required this.sessionsTooltip,
    required this.llmSettingsTooltip,
    required this.manageAgents,
    required this.newAgent,
    required this.agentNameLabel,
    required this.agentNameHint,
    required this.agentPromptLabel,
    required this.agentPromptHint,
    required this.agentModelLabel,
    required this.agentModelInheritDefault,
    required this.agentModelMissing,
    required this.editAgent,
    required this.updateAgent,
    required this.createAgent,
    required this.deleteAgent,
    required this.deleteAgentConfirmationTitle,
    required this.deleteAgentConfirmationMessage,
    required this.defaultAgentProtected,
    required this.messageHint,
    required this.editingMessageLabel,
    required this.cancelEditTooltip,
    required this.sendTooltip,
    required this.stopTooltip,
    required this.addAttachmentTooltip,
    required this.conversationAttachmentsTooltip,
    required this.terminalTitle,
    required this.menuNewTerminal,
    required this.menuCopyWorkspacePath,
    required this.menuCopyBranchName,
    required this.copiedToClipboard,
    required this.copyBranchNameUnavailable,
    required this.browserOptionsTooltip,
    required this.browserReload,
    required this.browserClearSession,
    required this.browserDebugHighlight,
    required this.browserDesktopMode,
    required this.browserMobileMode,
    required this.conversationAttachmentsTitle,
    required this.noConversationAttachmentsTitle,
    required this.noConversationAttachmentsDescription,
    required this.uploadedAttachmentLabel,
    required this.generatedAttachmentLabel,
    required this.editedFilesHeader,
    required this.showMoreFiles,
    required this.showLessFiles,
    required this.copyMessage,
    required this.selectAllMessage,
    required this.editMessage,
    required this.messageCopied,
    required this.jumpToLatestMessages,
    required this.imageLabel,
    required this.fileLabel,
    required this.galleryLabel,
    required this.cameraLabel,
    required this.skillsMenuLabel,
    required this.selectSkillsTitle,
    required this.connectingToNapaxi,
    required this.configureModelToChat,
    required this.stoppedMessage,
    required this.backgroundUnavailable,
    required this.notificationApproved,
    required this.notificationDenied,
    required this.sdkError,
    required this.evolutionQueued,
    required this.evolutionReviewing,
    required this.evolutionReviewed,
    required this.evolutionMemoryUpdated,
    required this.evolutionSkillUpdated,
    required this.evolutionPendingSuggestions,
    required this.evolutionFailed,
    required this.thinking,
    required this.thinkingDone,
    required this.skillsEnabled,
    required this.skillReasonMatched,
    required this.skillReasonContinued,
    required this.skillReasonTaskContext,
    required this.skillReasonLoaded,
    required this.skillReasonExplicit,
    required this.toolArguments,
    required this.toolResult,
    required this.toolOutput,
    required this.toolError,
    required this.toolRunning,
    required this.toolInterrupted,
    required this.toolAwaitingHuman,
    required this.humanRequestCancelled,
    required this.llmConfigurationTitle,
    required this.save,
    required this.addModel,
    required this.editModel,
    required this.selectModel,
    required this.deleteModel,
    required this.modelNameLabel,
    required this.modelNameHint,
    required this.providerLabel,
    required this.providerHint,
    required this.customProviderLabel,
    required this.fetchModels,
    required this.testConnection,
    required this.modelsLoaded,
    required this.connectionOk,
    required this.connectionFailed,
    required this.baseUrlRequiredForTest,
    required this.apiKeyRequiredForTest,
    required this.apiKeyInvalidForHeader,
    required this.noModelsFound,
    required this.openConfiguration,
    required this.noSavedModelsTitle,
    required this.modelCapabilitiesTitle,
    required this.addModelIdLabel,
    required this.addModelIdHint,
    required this.addModelId,
    required this.capabilityChat,
    required this.capabilityImageAnalysis,
    required this.capabilityImageGeneration,
    required this.capabilityVideoGeneration,
    required this.capabilityAudioAnalysis,
    required this.capabilitySlotsTitle,
    required this.noCapabilityModels,
    required this.capabilitySelectionCleared,
    required this.chooseChatModelToChat,
    required this.selectedModelLabel,
    required this.savedModelsTitle,
    required this.connectionTitle,
    required this.connectionDescription,
    required this.baseUrlLabel,
    required this.apiKeyLabel,
    required this.modelTitle,
    required this.modelDescription,
    required this.modelLabel,
    required this.maxTokensLabel,
    required this.maxTokensHint,
    required this.contextAdvancedTitle,
    required this.contextAdvancedDescription,
    required this.nativeContextWindowLabel,
    required this.nativeContextWindowHelp,
    required this.nativeContextWindowCustomLabel,
    required this.nativeContextWindowCustomHint,
    required this.contextWindowLabel,
    required this.contextWindowHelp,
    required this.contextWindowCustomLabel,
    required this.contextWindowCustomHint,
    required this.responseReserveLabel,
    required this.responseReserveHelp,
    required this.responseReserveCustomLabel,
    required this.responseReserveCustomHint,
    required this.compactionModelLabel,
    required this.compactionModelHint,
    required this.compactionModelFollowChat,
    required this.compactionModelHelp,
    required this.preCompactionMemoryFlushLabel,
    required this.preCompactionMemoryFlushDescription,
    required this.runtimeTitle,
    required this.runtimeDescription,
    required this.maxToolIterationsLabel,
    required this.maxToolIterationsHint,
    required this.promptingTitle,
    required this.promptingDescription,
    required this.systemPromptLabel,
    required this.systemPromptHint,
    required this.languageTitle,
    required this.languageDescription,
    required this.openSourceLicensesTitle,
    required this.openSourceLicensesDescription,
    required this.aboutTitle,
    required this.aboutTooltip,
    required this.settingsTitle,
    required this.settingsTooltip,
    required this.currentVersion,
    required this.versionLoading,
    required this.checkForUpdates,
    required this.noUpdateAvailable,
    required this.updateCheckUnavailable,
    required this.updateCheckFailed,
    required this.updateAvailableTitle,
    required this.updateVersionLine,
    required this.updateSize,
    required this.forceUpdate,
    required this.updateDescription,
    required this.noUpdateDescription,
    required this.updateNow,
    required this.later,
    required this.updateInstalling,
    required this.updateInstallerOpened,
    required this.updatePermissionRequired,
    required this.updateDownloadFailed,
    required this.updateUnknownError,
    required this.updateNoticeClose,
    required this.openInstallPage,
    required this.feedbackTitle,
    required this.feedbackContentLabel,
    required this.feedbackContentHint,
    required this.feedbackContactLabel,
    required this.feedbackContactHint,
    required this.feedbackContentRequired,
    required this.feedbackSubmitting,
    required this.feedbackSubmitted,
    required this.feedbackSubmitFailed,
    required this.feedbackContactUsPrompt,
    required this.feedbackShareTitle,
    required this.submit,
    required this.contactUs,
    required this.contactEmail,
    required this.contactDingTalkGroup,
    required this.contactWeChatGroup,
    required this.contactWeChatExpiredHint,
    required this.contactAdminWeChat,
    required this.copyEmail,
    required this.copyWeChatId,
    required this.saveQrCode,
    required this.qrCodeSaveFailed,
    required this.contactCopied,
    required this.newChat,
    required this.chatHistory,
    required this.filesTitle,
    required this.memoryFilesTitle,
    required this.workspaceFilesTitle,
    required this.journalFilesTitle,
    required this.recallFilesTitle,
    required this.noFilesTitle,
    required this.noFilesDescription,
    required this.fileLoadFailed,
    required this.fileOpenFailed,
    required this.deleteFile,
    required this.downloadFile,
    required this.shareFile,
    required this.selectedFilesCount,
    required this.deleteFileConfirmationTitle,
    required this.deleteFileConfirmationMessage,
    required this.cancel,
    required this.fileDeleted,
    required this.fileDownloaded,
    required this.fileActionFailed,
    required this.protectedMemoryFile,
    required this.configureToViewFiles,
    required this.skillsTitle,
    required this.scenariosTitle,
    required this.scenarioRefreshTooltip,
    required this.noScenariosTitle,
    required this.scenarioRiskLabel,
    required this.scenarioActivationLabel,
    required this.scenarioPlanesLabel,
    required this.scenarioSurfacesLabel,
    required this.scenarioMemoryLabel,
    required this.scenarioMissingLabel,
    required this.scenarioDisabledLabel,
    required this.scenarioUnavailableLabel,
    required this.scenarioActivationPlanTitle,
    required this.scenarioEnableLabel,
    required this.scenarioHostLabel,
    required this.scenarioRemoteLabel,
    required this.scenarioPolicyLabel,
    required this.scenarioWarningsLabel,
    required this.scenarioNoneValue,
    required this.scenarioEnabledStatus,
    required this.scenarioAvailableStatus,
    required this.scenarioUnavailableStatus,
    required this.scenarioCurrentLabel,
    required this.scenarioApplyHint,
    required this.scenarioApplyButton,
    required this.scenarioApplyingButton,
    required this.scenarioAppliedButton,
    required this.scenarioApplied,
    required this.scenarioPackLabel,
    required this.scenarioPackDescription,
    required this.developerEngineTitle,
    required this.developerEngineTooltip,
    required this.developerEngineUnavailable,
    required this.engineSettingsTitle,
    required this.engineSettingsDescription,
    required this.anthropicApiKeyLabel,
    required this.anthropicApiKeyHint,
    required this.openaiApiKeyLabel,
    required this.openaiApiKeyHint,
    required this.engineApiKeySaved,
    required this.apiBaseUrlLabel,
    required this.apiBaseUrlHint,
    required this.engineModelHint,
    required this.installedSkillsTitle,
    required this.skillStoreTitle,
    required this.noSkillsTitle,
    required this.noSkillsDescription,
    required this.searchSkillsHint,
    required this.skillSearchFailed,
    required this.noSkillStoreResultsTitle,
    required this.noSkillStoreResultsDescription,
    required this.installSkill,
    required this.updateSkill,
    required this.removeSkill,
    required this.installedSkill,
    required this.skillInstalled,
    required this.skillUpdated,
    required this.skillRemoved,
    required this.skillActionFailed,
    required this.removeSkillConfirmationTitle,
    required this.removeSkillConfirmationMessage,
    required this.configureToViewSkills,
    required this.favorites,
    required this.noFavoritesTitle,
    required this.noFavoritesDescription,
    required this.addFavorite,
    required this.removeFavorite,
    required this.recent,
    required this.currentChat,
    required this.pinned,
    required this.pinChat,
    required this.unpinChat,
    required this.deleteChat,
    required this.deleteChatConfirmationTitle,
    required this.deleteChatConfirmationMessage,
    required this.chatDeleted,
    required this.chatActionFailed,
    required this.emptyHistoryTitle,
    required this.emptyHistoryDescription,
    required this.searchHistoryTooltip,
    required this.searchHistoryHint,
    required this.searchHistoryNoResultsTitle,
    required this.searchHistoryNoResultsDescription,
  });

  final String appTitle;
  final String welcomeMessage;
  final String welcomeReadyMessage;
  final String noModelConfigured;
  final String sessionsTooltip;
  final String llmSettingsTooltip;
  final String manageAgents;
  final String newAgent;
  final String agentNameLabel;
  final String agentNameHint;
  final String agentPromptLabel;
  final String agentPromptHint;
  final String agentModelLabel;
  final String agentModelInheritDefault;
  final String Function(String profileId) agentModelMissing;
  final String editAgent;
  final String updateAgent;
  final String createAgent;
  final String deleteAgent;
  final String deleteAgentConfirmationTitle;
  final String Function(String agentName) deleteAgentConfirmationMessage;
  final String defaultAgentProtected;
  final String messageHint;
  final String editingMessageLabel;
  final String cancelEditTooltip;
  final String sendTooltip;
  final String stopTooltip;
  final String addAttachmentTooltip;
  final String conversationAttachmentsTooltip;
  final String terminalTitle;
  final String menuNewTerminal;
  final String menuCopyWorkspacePath;
  final String menuCopyBranchName;
  final String copiedToClipboard;
  final String copyBranchNameUnavailable;
  final String browserOptionsTooltip;
  final String browserReload;
  final String browserClearSession;
  final String browserDebugHighlight;
  final String browserDesktopMode;
  final String browserMobileMode;
  final String conversationAttachmentsTitle;
  final String noConversationAttachmentsTitle;
  final String noConversationAttachmentsDescription;
  final String uploadedAttachmentLabel;
  final String generatedAttachmentLabel;
  final String Function(int count) editedFilesHeader;
  final String Function(int count) showMoreFiles;
  final String showLessFiles;
  final String copyMessage;
  final String selectAllMessage;
  final String editMessage;
  final String messageCopied;
  final String jumpToLatestMessages;
  final String imageLabel;
  final String fileLabel;
  final String galleryLabel;
  final String cameraLabel;
  final String skillsMenuLabel;
  final String selectSkillsTitle;
  final String connectingToNapaxi;
  final String configureModelToChat;
  final String stoppedMessage;
  final String backgroundUnavailable;
  final String notificationApproved;
  final String notificationDenied;
  final String Function(String message) sdkError;
  final String evolutionQueued;
  final String evolutionReviewing;
  final String evolutionReviewed;
  final String evolutionMemoryUpdated;
  final String evolutionSkillUpdated;
  final String Function(int count) evolutionPendingSuggestions;
  final String evolutionFailed;
  final String thinking;
  final String thinkingDone;
  final String skillsEnabled;
  final String skillReasonMatched;
  final String skillReasonContinued;
  final String skillReasonTaskContext;
  final String skillReasonLoaded;
  final String skillReasonExplicit;
  final String toolArguments;
  final String toolResult;
  final String toolOutput;
  final String toolError;
  final String toolRunning;
  final String toolInterrupted;
  final String toolAwaitingHuman;
  final String humanRequestCancelled;
  final String llmConfigurationTitle;
  final String save;
  final String addModel;
  final String editModel;
  final String selectModel;
  final String deleteModel;
  final String modelNameLabel;
  final String modelNameHint;
  final String providerLabel;
  final String providerHint;
  final String customProviderLabel;
  final String fetchModels;
  final String testConnection;
  final String Function(int count) modelsLoaded;
  final String connectionOk;
  final String Function(String message) connectionFailed;
  final String baseUrlRequiredForTest;
  final String apiKeyRequiredForTest;
  final String apiKeyInvalidForHeader;
  final String noModelsFound;
  final String openConfiguration;
  final String noSavedModelsTitle;
  final String modelCapabilitiesTitle;
  final String addModelIdLabel;
  final String addModelIdHint;
  final String addModelId;
  final String capabilityChat;
  final String capabilityImageAnalysis;
  final String capabilityImageGeneration;
  final String capabilityVideoGeneration;
  final String capabilityAudioAnalysis;
  final String capabilitySlotsTitle;
  final String Function(String capability) noCapabilityModels;
  final String Function(String model, String capability)
  capabilitySelectionCleared;
  final String chooseChatModelToChat;
  final String selectedModelLabel;
  final String savedModelsTitle;
  final String connectionTitle;
  final String connectionDescription;
  final String baseUrlLabel;
  final String apiKeyLabel;
  final String modelTitle;
  final String modelDescription;
  final String modelLabel;
  final String maxTokensLabel;
  final String maxTokensHint;
  final String contextAdvancedTitle;
  final String contextAdvancedDescription;
  final String nativeContextWindowLabel;
  final String nativeContextWindowHelp;
  final String nativeContextWindowCustomLabel;
  final String nativeContextWindowCustomHint;
  final String contextWindowLabel;
  final String contextWindowHelp;
  final String contextWindowCustomLabel;
  final String contextWindowCustomHint;
  final String responseReserveLabel;
  final String responseReserveHelp;
  final String responseReserveCustomLabel;
  final String responseReserveCustomHint;
  final String compactionModelLabel;
  final String compactionModelHint;
  final String compactionModelFollowChat;
  final String compactionModelHelp;
  final String preCompactionMemoryFlushLabel;
  final String preCompactionMemoryFlushDescription;
  final String runtimeTitle;
  final String runtimeDescription;
  final String maxToolIterationsLabel;
  final String maxToolIterationsHint;
  final String promptingTitle;
  final String promptingDescription;
  final String systemPromptLabel;
  final String systemPromptHint;
  final String languageTitle;
  final String languageDescription;
  final String openSourceLicensesTitle;
  final String openSourceLicensesDescription;
  final String aboutTitle;
  final String aboutTooltip;
  final String settingsTitle;
  final String settingsTooltip;
  final String currentVersion;
  final String versionLoading;
  final String checkForUpdates;
  final String noUpdateAvailable;
  final String updateCheckUnavailable;
  final String Function(String message) updateCheckFailed;
  final String updateAvailableTitle;
  final String Function(String currentVersion, String latestVersion)
  updateVersionLine;
  final String Function(String size) updateSize;
  final String forceUpdate;
  final String updateDescription;
  final String noUpdateDescription;
  final String updateNow;
  final String later;
  final String updateInstalling;
  final String updateInstallerOpened;
  final String updatePermissionRequired;
  final String Function(String message) updateDownloadFailed;
  final String updateUnknownError;
  final String updateNoticeClose;
  final String openInstallPage;
  final String feedbackTitle;
  final String feedbackContentLabel;
  final String feedbackContentHint;
  final String feedbackContactLabel;
  final String feedbackContactHint;
  final String feedbackContentRequired;
  final String feedbackSubmitting;
  final String feedbackSubmitted;
  final String Function(String message) feedbackSubmitFailed;
  final String feedbackContactUsPrompt;
  final String feedbackShareTitle;
  final String submit;
  final String contactUs;
  final String contactEmail;
  final String contactDingTalkGroup;
  final String contactWeChatGroup;
  final String contactWeChatExpiredHint;
  final String contactAdminWeChat;
  final String copyEmail;
  final String copyWeChatId;
  final String saveQrCode;
  final String Function(String message) qrCodeSaveFailed;
  final String Function(String value) contactCopied;
  final String newChat;
  final String chatHistory;
  final String filesTitle;
  final String memoryFilesTitle;
  final String workspaceFilesTitle;
  final String journalFilesTitle;
  final String recallFilesTitle;
  final String noFilesTitle;
  final String noFilesDescription;
  final String Function(String message) fileLoadFailed;
  final String Function(String message) fileOpenFailed;
  final String deleteFile;
  final String downloadFile;
  final String shareFile;
  final String Function(int count) selectedFilesCount;
  final String deleteFileConfirmationTitle;
  final String Function(String filename) deleteFileConfirmationMessage;
  final String cancel;
  final String fileDeleted;
  final String fileDownloaded;
  final String Function(String message) fileActionFailed;
  final String protectedMemoryFile;
  final String configureToViewFiles;
  final String skillsTitle;
  final String scenariosTitle;
  final String scenarioRefreshTooltip;
  final String noScenariosTitle;
  final String scenarioRiskLabel;
  final String scenarioActivationLabel;
  final String scenarioPlanesLabel;
  final String scenarioSurfacesLabel;
  final String scenarioMemoryLabel;
  final String scenarioMissingLabel;
  final String scenarioDisabledLabel;
  final String scenarioUnavailableLabel;
  final String scenarioActivationPlanTitle;
  final String scenarioEnableLabel;
  final String scenarioHostLabel;
  final String scenarioRemoteLabel;
  final String scenarioPolicyLabel;
  final String scenarioWarningsLabel;
  final String scenarioNoneValue;
  final String scenarioEnabledStatus;
  final String scenarioAvailableStatus;
  final String scenarioUnavailableStatus;
  final String Function(String label) scenarioCurrentLabel;
  final String Function(String label) scenarioApplyHint;
  final String scenarioApplyButton;
  final String scenarioApplyingButton;
  final String scenarioAppliedButton;
  final String Function(String label) scenarioApplied;
  final String Function(String id, String fallback) scenarioPackLabel;
  final String Function(String id, String fallback) scenarioPackDescription;
  final String developerEngineTitle;
  final String developerEngineTooltip;
  final String developerEngineUnavailable;
  final String engineSettingsTitle;
  final String engineSettingsDescription;
  final String anthropicApiKeyLabel;
  final String anthropicApiKeyHint;
  final String openaiApiKeyLabel;
  final String openaiApiKeyHint;
  final String engineApiKeySaved;
  final String apiBaseUrlLabel;
  final String apiBaseUrlHint;
  final String engineModelHint;
  final String installedSkillsTitle;
  final String skillStoreTitle;
  final String noSkillsTitle;
  final String noSkillsDescription;
  final String searchSkillsHint;
  final String Function(String message) skillSearchFailed;
  final String noSkillStoreResultsTitle;
  final String noSkillStoreResultsDescription;
  final String installSkill;
  final String updateSkill;
  final String removeSkill;
  final String installedSkill;
  final String Function(String name) skillInstalled;
  final String Function(String name) skillUpdated;
  final String Function(String name) skillRemoved;
  final String Function(String message) skillActionFailed;
  final String removeSkillConfirmationTitle;
  final String Function(String name) removeSkillConfirmationMessage;
  final String configureToViewSkills;
  final String favorites;
  final String noFavoritesTitle;
  final String noFavoritesDescription;
  final String addFavorite;
  final String removeFavorite;
  final String recent;
  final String currentChat;
  final String pinned;
  final String pinChat;
  final String unpinChat;
  final String deleteChat;
  final String deleteChatConfirmationTitle;
  final String Function(String title) deleteChatConfirmationMessage;
  final String chatDeleted;
  final String Function(String message) chatActionFailed;
  final String emptyHistoryTitle;
  final String emptyHistoryDescription;
  final String searchHistoryTooltip;
  final String searchHistoryHint;
  final String searchHistoryNoResultsTitle;
  final String searchHistoryNoResultsDescription;

  static AppStrings of(BuildContext context) {
    return _AppLanguageScope.stringsOf(context);
  }

  static AppStrings forLanguage(AppLanguage language) {
    return switch (language) {
      AppLanguage.english => english,
      AppLanguage.chinese => chinese,
    };
  }

  static final english = AppStrings(
    appTitle: 'napaxi',
    welcomeMessage:
        'Welcome to napaxi. Open Basic configuration from Settings, then chat with the SDK-backed agent.',
    welcomeReadyMessage: 'napaxi is ready. Ask anything to start chatting.',
    noModelConfigured: 'No model configured',
    sessionsTooltip: 'Chat history',
    llmSettingsTooltip: 'Basic configuration',
    manageAgents: 'Manage agents',
    newAgent: 'New agent',
    agentNameLabel: 'Agent name',
    agentNameHint: 'Research assistant',
    agentPromptLabel: 'System prompt',
    agentPromptHint: 'Optional. Leave empty to inherit napaxi behavior.',
    agentModelLabel: 'Model',
    agentModelInheritDefault: 'Inherit default model',
    agentModelMissing: (profileId) =>
        'Model configuration "$profileId" is no longer available. Using the default model.',
    editAgent: 'Edit agent',
    updateAgent: 'Update agent',
    createAgent: 'Create agent',
    deleteAgent: 'Delete agent',
    deleteAgentConfirmationTitle: 'Delete agent?',
    deleteAgentConfirmationMessage: (agentName) =>
        'Delete "$agentName"? Sessions and workspace files are kept.',
    defaultAgentProtected: 'napaxi is the default agent and cannot be deleted.',
    messageHint: 'Message napaxi',
    editingMessageLabel: 'Editing',
    cancelEditTooltip: 'Cancel editing',
    sendTooltip: 'Send',
    stopTooltip: 'Stop',
    addAttachmentTooltip: 'Add attachment',
    conversationAttachmentsTooltip: 'Conversation attachments',
    terminalTitle: 'Terminal',
    menuNewTerminal: 'New Terminal',
    menuCopyWorkspacePath: 'Copy Workspace Path',
    menuCopyBranchName: 'Copy Branch Name',
    copiedToClipboard: 'Copied to clipboard',
    copyBranchNameUnavailable: 'Could not get current branch',
    browserOptionsTooltip: 'Browser options',
    browserReload: 'Reload',
    browserClearSession: 'Clear session',
    browserDebugHighlight: 'Highlight elements',
    browserDesktopMode: 'Desktop',
    browserMobileMode: 'Mobile',
    conversationAttachmentsTitle: 'Conversation attachments',
    noConversationAttachmentsTitle: 'No attachments yet',
    noConversationAttachmentsDescription:
        'Uploaded and generated files from this chat will appear here.',
    uploadedAttachmentLabel: 'Uploaded',
    generatedAttachmentLabel: 'Generated',
    editedFilesHeader: (count) => 'Edited $count file${count == 1 ? '' : 's'}',
    showMoreFiles: (count) => 'Show $count more',
    showLessFiles: 'Show less',
    copyMessage: 'Copy',
    selectAllMessage: 'Select all',
    editMessage: 'Edit',
    messageCopied: 'Message copied',
    jumpToLatestMessages: 'Latest',
    imageLabel: 'Image',
    fileLabel: 'File',
    galleryLabel: 'Gallery',
    cameraLabel: 'Camera',
    skillsMenuLabel: 'Skills',
    selectSkillsTitle: 'Select Skills',
    connectingToNapaxi: 'napaxi is working...',
    configureModelToChat:
        'Configure an LLM model and API key before chatting with napaxi.',
    stoppedMessage: 'Stopped.',
    backgroundUnavailable:
        'Notifications are off. You may not receive completion alerts.',
    notificationApproved: 'Confirmed from notification.',
    notificationDenied: 'Denied from notification.',
    sdkError: (message) => 'napaxi error: $message',
    evolutionQueued: 'Learning from this chat in the background.',
    evolutionReviewing: 'Reviewing',
    evolutionReviewed: 'Reviewed',
    evolutionMemoryUpdated: 'Memory updated',
    evolutionSkillUpdated: 'Skill improved',
    evolutionPendingSuggestions: (count) =>
        '$count suggestion${count == 1 ? '' : 's'} pending',
    evolutionFailed: 'Review not completed',
    thinking: 'Thinking',
    thinkingDone: 'Thought through',
    skillsEnabled: 'Skills enabled',
    skillReasonMatched: 'Matched',
    skillReasonContinued: 'Continued',
    skillReasonTaskContext: 'Task context',
    skillReasonLoaded: 'Loaded',
    skillReasonExplicit: 'Explicit',
    toolArguments: 'Arguments',
    toolResult: 'Result',
    toolOutput: 'Output',
    toolError: 'Error',
    toolRunning: 'Running',
    toolInterrupted: 'Interrupted',
    toolAwaitingHuman: 'Awaiting reply',
    humanRequestCancelled: 'Cancelled',
    llmConfigurationTitle: 'Basic configuration',
    save: 'Save',
    addModel: 'Add model',
    editModel: 'Edit model',
    selectModel: 'Select model',
    deleteModel: 'Delete model',
    modelNameLabel: 'Configuration name',
    modelNameHint: 'Work assistant',
    providerLabel: 'Provider',
    providerHint: 'openai-compatible',
    customProviderLabel: 'Custom provider',
    fetchModels: 'Fetch models',
    testConnection: 'Test connection',
    modelsLoaded: (count) => '$count models loaded',
    connectionOk: 'Connection looks good',
    connectionFailed: (message) => 'Connection failed: $message',
    baseUrlRequiredForTest: 'Enter a Base URL before connecting.',
    apiKeyRequiredForTest: 'Enter an API key before testing.',
    apiKeyInvalidForHeader:
        'API Key contains unsupported characters. Paste the raw key only.',
    noModelsFound: 'No models returned. You can still enter one manually.',
    openConfiguration: 'Open basic configuration',
    noSavedModelsTitle: 'No models yet',
    modelCapabilitiesTitle: 'Model capabilities',
    addModelIdLabel: 'Model ID',
    addModelIdHint: 'model-id',
    addModelId: 'Add model ID',
    capabilityChat: 'Chat',
    capabilityImageAnalysis: 'Image analysis',
    capabilityImageGeneration: 'Image generation',
    capabilityVideoGeneration: 'Video generation',
    capabilityAudioAnalysis: 'Audio analysis',
    capabilitySlotsTitle: 'Capability slots',
    noCapabilityModels: (capability) =>
        'Add a model that supports $capability to enable this slot.',
    capabilitySelectionCleared: (model, capability) =>
        '$model was removed from $capability because that capability was turned off.',
    chooseChatModelToChat: 'Choose a chat model before chatting.',
    selectedModelLabel: 'Selected',
    savedModelsTitle: 'Models',
    connectionTitle: 'Connection',
    connectionDescription:
        'These fields are used to initialize the local SDK engine.',
    baseUrlLabel: 'Base URL',
    apiKeyLabel: 'API Key',
    modelTitle: 'Model',
    modelDescription: 'The selected model is used for SDK requests.',
    modelLabel: 'Model',
    maxTokensLabel: 'Output tokens',
    maxTokensHint: '40960',
    contextAdvancedTitle: 'Context',
    contextAdvancedDescription:
        'These settings only affect this profile when it is used as the main reasoning/chat model.',
    nativeContextWindowLabel: 'Native context window',
    nativeContextWindowHelp:
        'The model/provider advertised limit. It explains capacity but does not force the whole window to be used.',
    nativeContextWindowCustomLabel: 'Custom native window',
    nativeContextWindowCustomHint: '1000000',
    contextWindowLabel: 'Effective context budget',
    contextWindowHelp:
        'The actual budget used for planning, pruning, compaction, and overflow checks.',
    contextWindowCustomLabel: 'Custom effective budget',
    contextWindowCustomHint: '1000000',
    responseReserveLabel: 'Response reserve',
    responseReserveHelp:
        'Tokens kept for the model answer. The prompt budget is the effective budget minus this reserve.',
    responseReserveCustomLabel: 'Custom response reserve',
    responseReserveCustomHint: '8192',
    compactionModelLabel: 'Compaction model',
    compactionModelHint: 'Use chat model by default',
    compactionModelFollowChat: 'Follow chat model',
    compactionModelHelp:
        'Optional model id under the same provider, API key, and Base URL. Cross-provider compaction is not supported here yet.',
    preCompactionMemoryFlushLabel: 'Memory flush before compaction',
    preCompactionMemoryFlushDescription:
        'Experimental: review durable memory before automatic compaction.',
    runtimeTitle: 'Runtime',
    runtimeDescription: 'Controls how long model and tool turns may continue.',
    maxToolIterationsLabel: 'Tool rounds',
    maxToolIterationsHint: '50, or -1 for unlimited',
    promptingTitle: 'Prompting',
    promptingDescription: 'Optional defaults for real LLM requests.',
    systemPromptLabel: 'System Prompt',
    systemPromptHint: 'Optional instructions for future integration',
    languageTitle: 'Language',
    languageDescription: 'Choose the language used by the demo interface.',
    openSourceLicensesTitle: 'Open source licenses',
    openSourceLicensesDescription: 'Review third-party package licenses.',
    aboutTitle: 'About',
    aboutTooltip: 'About',
    settingsTitle: 'Settings',
    settingsTooltip: 'Settings',
    currentVersion: 'Current version',
    versionLoading: 'Loading...',
    checkForUpdates: 'Check for updates',
    noUpdateAvailable: 'You are using the latest version.',
    updateCheckUnavailable: 'Update checking is not available.',
    updateCheckFailed: (message) => 'Update check failed: $message',
    updateAvailableTitle: 'Update available',
    updateVersionLine: (currentVersion, latestVersion) =>
        'Current $currentVersion, latest $latestVersion',
    updateSize: (size) => 'Download size: $size',
    forceUpdate: 'This update is required.',
    updateDescription: 'What changed',
    noUpdateDescription: 'No release notes were provided.',
    updateNow: 'Update now',
    later: 'Later',
    updateInstalling: 'Downloading update...',
    updateInstallerOpened: 'Android installer opened.',
    updatePermissionRequired:
        'Install permission is required. The Android settings page has been opened.',
    updateDownloadFailed: (message) => 'Could not install update: $message',
    updateUnknownError: 'Unknown error',
    updateNoticeClose: 'Got it',
    openInstallPage: 'Open Pgyer page',
    feedbackTitle: 'Feedback',
    feedbackContentLabel: 'Issue',
    feedbackContentHint: 'Tell us what happened.',
    feedbackContactLabel: 'Contact',
    feedbackContactHint: 'Email or phone, optional',
    feedbackContentRequired: 'Describe the issue before submitting.',
    feedbackSubmitting: 'Submitting...',
    feedbackSubmitted: 'Feedback submitted.',
    feedbackSubmitFailed: (message) => 'Could not submit feedback: $message',
    feedbackContactUsPrompt:
        'For screenshots, long descriptions, or group support, contact us directly.',
    feedbackShareTitle: 'napaxi feedback',
    submit: 'Submit',
    contactUs: 'Contact us',
    contactEmail: 'Email',
    contactDingTalkGroup: 'DingTalk community',
    contactWeChatGroup: 'WeChat community',
    contactWeChatExpiredHint:
        'The WeChat QR code may expire. Add the admin if scanning no longer works.',
    contactAdminWeChat: 'Admin WeChat',
    copyEmail: 'Copy email',
    copyWeChatId: 'Copy WeChat ID',
    saveQrCode: 'Save QR code',
    qrCodeSaveFailed: (message) => 'Could not save QR code: $message',
    contactCopied: (value) => 'Copied $value',
    newChat: 'Chat',
    chatHistory: 'Chat history',
    filesTitle: 'Files',
    memoryFilesTitle: 'Memory',
    workspaceFilesTitle: 'Workspace',
    journalFilesTitle: 'Journal',
    recallFilesTitle: 'Recall',
    noFilesTitle: 'No files yet',
    noFilesDescription: 'Files created by the agent will appear here.',
    fileLoadFailed: (message) => 'Could not load files: $message',
    fileOpenFailed: (message) => 'Could not open file: $message',
    deleteFile: 'Delete',
    downloadFile: 'Save copy',
    shareFile: 'Send',
    selectedFilesCount: (count) => '$count selected',
    deleteFileConfirmationTitle: 'Delete file?',
    deleteFileConfirmationMessage: (filename) =>
        'Delete "$filename"? This cannot be undone.',
    cancel: 'Cancel',
    fileDeleted: 'File deleted',
    fileDownloaded: 'File saved',
    fileActionFailed: (message) => 'File action failed: $message',
    protectedMemoryFile: 'This memory file is required and cannot be deleted.',
    configureToViewFiles:
        'Configure an LLM model and API key before viewing files.',
    skillsTitle: 'Skills',
    scenariosTitle: 'Scenarios',
    scenarioRefreshTooltip: 'Refresh',
    noScenariosTitle: 'No scenarios registered',
    scenarioRiskLabel: 'Risk',
    scenarioActivationLabel: 'Activation',
    scenarioPlanesLabel: 'Planes',
    scenarioSurfacesLabel: 'Surfaces',
    scenarioMemoryLabel: 'Memory',
    scenarioMissingLabel: 'Missing',
    scenarioDisabledLabel: 'Disabled',
    scenarioUnavailableLabel: 'Unavailable',
    scenarioActivationPlanTitle: 'Activation plan',
    scenarioEnableLabel: 'Enable',
    scenarioHostLabel: 'Host',
    scenarioRemoteLabel: 'Remote',
    scenarioPolicyLabel: 'Policy',
    scenarioWarningsLabel: 'Warnings',
    scenarioNoneValue: 'none',
    scenarioEnabledStatus: 'Enabled',
    scenarioAvailableStatus: 'Available',
    scenarioUnavailableStatus: 'Unavailable',
    scenarioCurrentLabel: (label) => 'Current scenario: $label',
    scenarioApplyHint: (label) =>
        'Switch to $label to use its tools, project views, and history.',
    scenarioApplyButton: 'Apply',
    scenarioApplyingButton: 'Applying',
    scenarioAppliedButton: 'Active',
    scenarioApplied: (label) => '$label applied',
    scenarioPackLabel: (id, fallback) => switch (id) {
      'napaxi.scenario.general' => 'General',
      'napaxi.scenario.mobile_development' => 'Developer Workbench',
      _ => fallback,
    },
    scenarioPackDescription: (id, fallback) => switch (id) {
      'napaxi.scenario.general' => 'Chat, files, memory, and common skills.',
      'napaxi.scenario.mobile_development' =>
        'Android projects, Git, builds, and environment setup.',
      _ => fallback,
    },
    developerEngineTitle: 'Development engine',
    developerEngineTooltip: 'Switch development engine',
    developerEngineUnavailable: 'Not installed',
    engineSettingsTitle: 'Engine Settings',
    engineSettingsDescription: 'Configure API keys for external CLI engines.',
    anthropicApiKeyLabel: 'Anthropic API Key',
    anthropicApiKeyHint: 'sk-ant-...',
    openaiApiKeyLabel: 'OpenAI API Key',
    openaiApiKeyHint: 'sk-...',
    engineApiKeySaved: 'API key saved',
    apiBaseUrlLabel: 'API Base URL',
    apiBaseUrlHint: 'https://api.example.com (optional)',
    engineModelHint: 'e.g. claude-sonnet-4-20250514 (optional)',
    installedSkillsTitle: 'Installed',
    skillStoreTitle: 'Store',
    noSkillsTitle: 'No skills installed',
    noSkillsDescription: 'Install a skill from the store to extend this agent.',
    searchSkillsHint: 'Search',
    skillSearchFailed: (message) => 'Could not load skills: $message',
    noSkillStoreResultsTitle: 'No skills found',
    noSkillStoreResultsDescription: 'Try a different search term.',
    installSkill: 'Install',
    updateSkill: 'Update',
    removeSkill: 'Remove',
    installedSkill: 'Installed',
    skillInstalled: (name) => '$name installed',
    skillUpdated: (name) => '$name updated',
    skillRemoved: (name) => '$name removed',
    skillActionFailed: (message) => 'Skill action failed: $message',
    removeSkillConfirmationTitle: 'Remove skill?',
    removeSkillConfirmationMessage: (name) => 'Remove "$name" from this agent?',
    configureToViewSkills:
        'Configure an LLM model and API key before managing skills.',
    favorites: 'Favorites',
    noFavoritesTitle: 'No favorites yet',
    noFavoritesDescription: 'Tap the star on any attachment to keep it here.',
    addFavorite: 'Add to favorites',
    removeFavorite: 'Remove from favorites',
    recent: 'Recent',
    currentChat: 'Current',
    pinned: 'Pinned',
    pinChat: 'Pin',
    unpinChat: 'Unpin',
    deleteChat: 'Delete',
    deleteChatConfirmationTitle: 'Delete chat?',
    deleteChatConfirmationMessage: (title) =>
        'Delete "$title"? This cannot be undone.',
    chatDeleted: 'Chat deleted',
    chatActionFailed: (message) => 'Chat action failed: $message',
    emptyHistoryTitle: 'No chats yet',
    emptyHistoryDescription: 'Start a new chat and it will appear here.',
    searchHistoryTooltip: 'Search',
    searchHistoryHint: 'Search',
    searchHistoryNoResultsTitle: 'No matching chats',
    searchHistoryNoResultsDescription: 'Try a different keyword.',
  );

  static final chinese = AppStrings(
    appTitle: 'napaxi',
    welcomeMessage: '欢迎使用 napaxi。请从设置里的“基础配置”添加模型，然后开始对话。',
    welcomeReadyMessage: 'napaxi 已准备好，可以直接开始对话。',
    noModelConfigured: '未配置模型',
    sessionsTooltip: '会话历史',
    llmSettingsTooltip: '基础配置',
    manageAgents: '管理 Agent',
    newAgent: '新建 Agent',
    agentNameLabel: 'Agent 名称',
    agentNameHint: '研究助手',
    agentPromptLabel: '系统提示词',
    agentPromptHint: '可选。留空则继承 napaxi 的默认行为。',
    agentModelLabel: '模型',
    agentModelInheritDefault: '继承默认模型',
    agentModelMissing: (profileId) => '模型配置“$profileId”已不可用，已使用默认模型。',
    editAgent: '编辑 Agent',
    updateAgent: '更新 Agent',
    createAgent: '创建 Agent',
    deleteAgent: '删除 Agent',
    deleteAgentConfirmationTitle: '删除 Agent？',
    deleteAgentConfirmationMessage: (agentName) =>
        '确定删除“$agentName”吗？会话和工作区文件会保留。',
    defaultAgentProtected: 'napaxi 是默认 Agent，不能删除。',
    messageHint: '给 napaxi 发消息',
    editingMessageLabel: '编辑',
    cancelEditTooltip: '取消编辑',
    sendTooltip: '发送',
    stopTooltip: '停止',
    addAttachmentTooltip: '添加附件',
    conversationAttachmentsTooltip: '本次对话附件',
    terminalTitle: '终端',
    menuNewTerminal: '新建终端',
    menuCopyWorkspacePath: '复制工作区路径',
    menuCopyBranchName: '复制分支名',
    copiedToClipboard: '已复制到剪贴板',
    copyBranchNameUnavailable: '无法获取当前分支',
    browserOptionsTooltip: '浏览器选项',
    browserReload: '重新加载',
    browserClearSession: '清除浏览器会话',
    browserDebugHighlight: '高亮可点元素',
    browserDesktopMode: '桌面版',
    browserMobileMode: '手机版',
    conversationAttachmentsTitle: '本次对话附件',
    noConversationAttachmentsTitle: '暂无附件',
    noConversationAttachmentsDescription: '本次对话上传、生成或修改的文件会显示在这里。',
    uploadedAttachmentLabel: '上传',
    generatedAttachmentLabel: '生成',
    editedFilesHeader: (count) => '已编辑 $count 个文件',
    showMoreFiles: (count) => '再显示 $count 个文件',
    showLessFiles: '收起',
    copyMessage: '复制',
    selectAllMessage: '全选',
    editMessage: '编辑',
    messageCopied: '消息已复制',
    jumpToLatestMessages: '查看最新',
    imageLabel: '图片',
    fileLabel: '文件',
    galleryLabel: '相册',
    cameraLabel: '相机',
    skillsMenuLabel: '技能',
    selectSkillsTitle: '选择技能',
    connectingToNapaxi: 'napaxi 正在处理...',
    configureModelToChat: '请先配置 LLM 模型和 API Key，再和 napaxi 对话。',
    stoppedMessage: '已停止。',
    backgroundUnavailable: '通知未开启，可能收不到完成提醒。',
    notificationApproved: '已从通知确认。',
    notificationDenied: '已从通知拒绝。',
    sdkError: (message) => 'napaxi 错误：$message',
    evolutionQueued: '正在后台学习这次对话。',
    evolutionReviewing: '复盘中',
    evolutionReviewed: '已复盘',
    evolutionMemoryUpdated: '已更新记忆',
    evolutionSkillUpdated: '已优化技能',
    evolutionPendingSuggestions: (count) => '有 $count 条建议待确认',
    evolutionFailed: '复盘未完成',
    thinking: '思考中',
    thinkingDone: '已思考',
    skillsEnabled: '已启用技能',
    skillReasonMatched: '匹配触发',
    skillReasonContinued: '继续使用',
    skillReasonTaskContext: '任务续用',
    skillReasonLoaded: '已加载',
    skillReasonExplicit: '显式指定',
    toolArguments: '参数',
    toolResult: '结果',
    toolOutput: '输出',
    toolError: '错误',
    toolRunning: '运行中',
    toolInterrupted: '已中断',
    toolAwaitingHuman: '等待回答',
    humanRequestCancelled: '已取消',
    llmConfigurationTitle: '基础配置',
    save: '保存',
    addModel: '新增模型',
    editModel: '编辑模型',
    selectModel: '选择模型',
    deleteModel: '删除模型',
    modelNameLabel: '配置名称',
    modelNameHint: '工作助手',
    providerLabel: '服务商',
    providerHint: 'openai-compatible',
    customProviderLabel: '自定义服务商',
    fetchModels: '获取模型',
    testConnection: '测试连接',
    modelsLoaded: (count) => '已获取 $count 个模型',
    connectionOk: '连接正常',
    connectionFailed: (message) => '连接失败：$message',
    baseUrlRequiredForTest: '请先填写 Base URL 再连接。',
    apiKeyRequiredForTest: '请先填写 API Key 再测试。',
    apiKeyInvalidForHeader: 'API Key 包含无法用于请求头的字符，请只粘贴原始 key。',
    noModelsFound: '接口没有返回模型，也可以手动填写。',
    openConfiguration: '打开基础配置',
    noSavedModelsTitle: '还没有模型',
    modelCapabilitiesTitle: '模型能力',
    addModelIdLabel: '模型 ID',
    addModelIdHint: 'model-id',
    addModelId: '添加模型 ID',
    capabilityChat: '聊天',
    capabilityImageAnalysis: '图片分析',
    capabilityImageGeneration: '图片生成',
    capabilityVideoGeneration: '视频生成',
    capabilityAudioAnalysis: '语音分析',
    capabilitySlotsTitle: '能力槽位',
    noCapabilityModels: (capability) => '添加支持$capability的模型后可选择。',
    capabilitySelectionCleared: (model, capability) =>
        '$model 已从$capability槽位清空，因为该能力已关闭。',
    chooseChatModelToChat: '请先选择聊天模型，再开始对话。',
    selectedModelLabel: '已选择',
    savedModelsTitle: '模型',
    connectionTitle: '连接',
    connectionDescription: '这些字段会用于初始化本地 SDK 引擎。',
    baseUrlLabel: 'Base URL',
    apiKeyLabel: 'API Key',
    modelTitle: '模型',
    modelDescription: '所选模型会用于 SDK 请求。',
    modelLabel: '模型',
    maxTokensLabel: '输出 Token',
    maxTokensHint: '40960',
    contextAdvancedTitle: '上下文',
    contextAdvancedDescription: '这些设置仅在该模型作为主力推理/聊天模型时生效。',
    nativeContextWindowLabel: '原生上下文窗口',
    nativeContextWindowHelp: '模型或 provider 宣称的理论窗口，用于说明容量，不代表会把窗口全部用满。',
    nativeContextWindowCustomLabel: '自定义原生窗口',
    nativeContextWindowCustomHint: '1000000',
    contextWindowLabel: '有效上下文预算',
    contextWindowHelp: '实际用于预算、工具裁剪、上下文压缩和超限判断的窗口。',
    contextWindowCustomLabel: '自定义有效预算',
    contextWindowCustomHint: '1000000',
    responseReserveLabel: '回复预留',
    responseReserveHelp: '预留给模型输出的 token；可用 prompt 预算约等于有效预算减去回复预留。',
    responseReserveCustomLabel: '自定义回复预留',
    responseReserveCustomHint: '8192',
    compactionModelLabel: '压缩模型',
    compactionModelHint: '默认使用当前聊天模型',
    compactionModelFollowChat: '跟随当前聊天模型',
    compactionModelHelp:
        '可选：同一 provider/API Key/Base URL 下的模型 ID。这里暂不支持跨 provider 压缩。',
    preCompactionMemoryFlushLabel: '压缩前刷新记忆',
    preCompactionMemoryFlushDescription: '实验功能：自动压缩前先静默整理长期记忆。',
    runtimeTitle: '运行时',
    runtimeDescription: '控制模型和工具调用可以持续进行多少轮。',
    maxToolIterationsLabel: '工具轮数',
    maxToolIterationsHint: '50，或 -1 表示不限',
    promptingTitle: '提示词',
    promptingDescription: '用于真实 LLM 请求的可选默认值。',
    systemPromptLabel: '系统提示词',
    systemPromptHint: '后续集成时使用的可选指令',
    languageTitle: '语言',
    languageDescription: '选择 demo 界面的显示语言。',
    openSourceLicensesTitle: '开源许可',
    openSourceLicensesDescription: '查看第三方依赖的许可证。',
    aboutTitle: '关于',
    aboutTooltip: '关于',
    settingsTitle: '设置',
    settingsTooltip: '设置',
    currentVersion: '当前版本',
    versionLoading: '加载中...',
    checkForUpdates: '检查更新',
    noUpdateAvailable: '当前已是最新版本。',
    updateCheckUnavailable: '暂不可检查更新。',
    updateCheckFailed: (message) => '检查更新失败：$message',
    updateAvailableTitle: '发现新版本',
    updateVersionLine: (currentVersion, latestVersion) =>
        '当前 $currentVersion，最新 $latestVersion',
    updateSize: (size) => '安装包大小：$size',
    forceUpdate: '这是一个强制更新版本。',
    updateDescription: '更新内容',
    noUpdateDescription: '暂无更新说明。',
    updateNow: '立即更新',
    later: '稍后',
    updateInstalling: '正在下载更新...',
    updateInstallerOpened: '已打开 Android 安装器。',
    updatePermissionRequired: '需要允许安装未知来源应用，已打开 Android 设置页。',
    updateDownloadFailed: (message) => '无法安装更新：$message',
    updateUnknownError: '未知错误',
    updateNoticeClose: '知道了',
    openInstallPage: '打开蒲公英页面',
    feedbackTitle: '问题反馈',
    feedbackContentLabel: '问题描述',
    feedbackContentHint: '请描述遇到的问题。',
    feedbackContactLabel: '联系方式',
    feedbackContactHint: '邮箱或手机号，可选',
    feedbackContentRequired: '请先填写问题描述。',
    feedbackSubmitting: '提交中...',
    feedbackSubmitted: '反馈已提交。',
    feedbackSubmitFailed: (message) => '提交反馈失败：$message',
    feedbackContactUsPrompt: '如果需要发送截图、补充长文本或进群交流，可以直接联系我们。',
    feedbackShareTitle: 'napaxi 问题反馈',
    submit: '提交',
    contactUs: '联系我们',
    contactEmail: '邮箱',
    contactDingTalkGroup: '钉钉交流群',
    contactWeChatGroup: '微信交流群',
    contactWeChatExpiredHint: '微信群二维码可能会过期。如果无法扫码入群，请添加管理员微信拉你进群。',
    contactAdminWeChat: '管理员微信',
    copyEmail: '复制邮箱',
    copyWeChatId: '复制微信号',
    saveQrCode: '保存二维码',
    qrCodeSaveFailed: (message) => '保存二维码失败：$message',
    contactCopied: (value) => '已复制：$value',
    newChat: '聊天',
    chatHistory: '会话历史',
    filesTitle: '文件',
    memoryFilesTitle: '记忆',
    workspaceFilesTitle: '工作区',
    journalFilesTitle: '日志',
    recallFilesTitle: '召回',
    noFilesTitle: '暂无文件',
    noFilesDescription: 'Agent 创建的文件会显示在这里。',
    fileLoadFailed: (message) => '无法加载文件：$message',
    fileOpenFailed: (message) => '无法打开文件：$message',
    deleteFile: '删除',
    downloadFile: '保存副本',
    shareFile: '发送',
    selectedFilesCount: (count) => '已选择 $count 项',
    deleteFileConfirmationTitle: '删除文件？',
    deleteFileConfirmationMessage: (filename) => '确定删除“$filename”吗？此操作无法撤销。',
    cancel: '取消',
    fileDeleted: '文件已删除',
    fileDownloaded: '文件已保存',
    fileActionFailed: (message) => '文件操作失败：$message',
    protectedMemoryFile: '这个记忆文件是关键文件，不能删除。',
    configureToViewFiles: '请先配置 LLM 模型和 API Key，再查看文件。',
    skillsTitle: '技能',
    scenariosTitle: '场景',
    scenarioRefreshTooltip: '刷新',
    noScenariosTitle: '暂无已注册场景',
    scenarioRiskLabel: '风险',
    scenarioActivationLabel: '激活方式',
    scenarioPlanesLabel: '执行平面',
    scenarioSurfacesLabel: '界面',
    scenarioMemoryLabel: '记忆范围',
    scenarioMissingLabel: '缺失',
    scenarioDisabledLabel: '未启用',
    scenarioUnavailableLabel: '不可用',
    scenarioActivationPlanTitle: '激活计划',
    scenarioEnableLabel: '启用',
    scenarioHostLabel: '宿主',
    scenarioRemoteLabel: '远端',
    scenarioPolicyLabel: '策略',
    scenarioWarningsLabel: '提醒',
    scenarioNoneValue: '无',
    scenarioEnabledStatus: '已启用',
    scenarioAvailableStatus: '可用',
    scenarioUnavailableStatus: '不可用',
    scenarioCurrentLabel: (label) => '当前场景：$label',
    scenarioApplyHint: (label) => '切换后，会使用$label对应的工具、项目视图和历史。',
    scenarioApplyButton: '应用',
    scenarioApplyingButton: '应用中',
    scenarioAppliedButton: '使用中',
    scenarioApplied: (label) => '已应用 $label',
    scenarioPackLabel: (id, fallback) => switch (id) {
      'napaxi.scenario.general' => '通用',
      'napaxi.scenario.mobile_development' => '开发工作台',
      _ => fallback,
    },
    scenarioPackDescription: (id, fallback) => switch (id) {
      'napaxi.scenario.general' => '日常对话、文件、记忆和常用技能。',
      'napaxi.scenario.mobile_development' => 'Android 项目、Git、构建和环境配置。',
      _ => fallback,
    },
    developerEngineTitle: '开发引擎',
    developerEngineTooltip: '切换开发引擎',
    developerEngineUnavailable: '未安装',
    engineSettingsTitle: '引擎配置',
    engineSettingsDescription: '配置外部 CLI 引擎的 API Key。',
    anthropicApiKeyLabel: 'Anthropic API Key',
    anthropicApiKeyHint: 'sk-ant-...',
    openaiApiKeyLabel: 'OpenAI API Key',
    openaiApiKeyHint: 'sk-...',
    engineApiKeySaved: 'API Key 已保存',
    apiBaseUrlLabel: 'API Base URL',
    apiBaseUrlHint: 'https://api.example.com（选填）',
    engineModelHint: '例如 claude-sonnet-4-20250514（选填）',
    installedSkillsTitle: '已安装',
    skillStoreTitle: '商店',
    noSkillsTitle: '还没有安装技能',
    noSkillsDescription: '从商店安装技能，扩展当前 Agent。',
    searchSkillsHint: '搜索',
    skillSearchFailed: (message) => '无法加载技能：$message',
    noSkillStoreResultsTitle: '没有找到技能',
    noSkillStoreResultsDescription: '换个关键词试试。',
    installSkill: '安装',
    updateSkill: '更新',
    removeSkill: '移除',
    installedSkill: '已安装',
    skillInstalled: (name) => '已安装 $name',
    skillUpdated: (name) => '已更新 $name',
    skillRemoved: (name) => '已移除 $name',
    skillActionFailed: (message) => '技能操作失败：$message',
    removeSkillConfirmationTitle: '移除技能？',
    removeSkillConfirmationMessage: (name) => '确定从当前 Agent 移除“$name”吗？',
    configureToViewSkills: '请先配置 LLM 模型和 API Key，再管理技能。',
    favorites: '收藏',
    noFavoritesTitle: '还没有收藏',
    noFavoritesDescription: '点击任意附件上的星星，就会保存在这里。',
    addFavorite: '收藏附件',
    removeFavorite: '取消收藏',
    recent: '最近',
    currentChat: '当前',
    pinned: '置顶',
    pinChat: '置顶',
    unpinChat: '取消置顶',
    deleteChat: '删除',
    deleteChatConfirmationTitle: '删除会话？',
    deleteChatConfirmationMessage: (title) => '确定删除“$title”吗？此操作无法撤销。',
    chatDeleted: '会话已删除',
    chatActionFailed: (message) => '会话操作失败：$message',
    emptyHistoryTitle: '还没有会话',
    emptyHistoryDescription: '开始新会话后，会话会显示在这里。',
    searchHistoryTooltip: '搜索',
    searchHistoryHint: '搜索',
    searchHistoryNoResultsTitle: '没有匹配会话',
    searchHistoryNoResultsDescription: '换个关键词试试。',
  );
}
