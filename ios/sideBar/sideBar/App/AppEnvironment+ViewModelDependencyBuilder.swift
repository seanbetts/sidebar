import Foundation
import sideBarShared

// swiftlint:disable nesting
extension AppEnvironment {
    struct ViewModelDependencyBuilder {
        struct WorkspaceContextSection: Equatable {
            let pane: WorkspacePane
            let section: AppSection
        }

        struct Output {
            let chatViewModel: ChatViewModel
            let notesRuntime: NotesRuntime
            let notesViewModel: NotesViewModel
            let notesEditorViewModel: NotesEditorViewModel
            let ingestionViewModel: IngestionViewModel
            let websitesViewModel: WebsitesViewModel
            let tasksViewModel: TasksViewModel
            let memoriesViewModel: MemoriesViewModel
            let settingsViewModel: SettingsViewModel
            let weatherViewModel: WeatherViewModel
            let currentLocationViewModel: CurrentLocationViewModel
        }

        private static func makeSettingsViewModel(container: ServiceContainer) -> SettingsViewModel {
            SettingsViewModel(
                settingsAPI: container.settingsAPI,
                skillsAPI: container.skillsAPI,
                cache: container.cacheClient,
                currentAuthUserIdProvider: {
                    settingsRequestUserId(
                        authSession: container.authSession,
                        requireAuthorization: false
                    )
                },
                currentAuthorizedUserIdProvider: {
                    settingsRequestUserId(
                        authSession: container.authSession,
                        requireAuthorization: true
                    )
                },
                refreshAuthorizedSession: {
                    await container.authSession.refreshSession()
                }
            )
        }

        static func settingsRequestUserId(
            authSession: AuthSession,
            requireAuthorization: Bool
        ) -> String? {
            guard let authorizationToken = authSession.authorizationToken else {
                return requireAuthorization ? nil : authSession.userId
            }
            if let tokenSubject = SupabaseAuthAdapter.jwtSubject(from: authorizationToken) {
                return tokenSubject
            }
            return authSession.userId
        }

        static func orderedWorkspaceContextSections(
            workspaceState: WorkspaceState?
        ) -> [WorkspaceContextSection] {
            guard let workspaceState else {
                return []
            }

            var visible: [WorkspaceContextSection] = []
            if let section = WorkspaceLegacySectionAdapter.section(
                from: workspaceState.primaryPane.descriptor
            ) {
                visible.append(WorkspaceContextSection(pane: .primary, section: section))
            }
            if workspaceState.layout != .compact,
               let secondaryPane = workspaceState.secondaryPane,
               let section = WorkspaceLegacySectionAdapter.section(from: secondaryPane.descriptor) {
                visible.append(WorkspaceContextSection(pane: .secondary, section: section))
            }

            guard let focusedPane = resolveFocusedPane(
                workspaceState: workspaceState,
                visibleSections: visible
            ) else {
                return visible
            }

            return visible.sorted { lhs, rhs in
                if lhs.pane == rhs.pane {
                    return false
                }
                if lhs.pane == focusedPane {
                    return true
                }
                if rhs.pane == focusedPane {
                    return false
                }
                return lhs.pane == .primary
            }
        }

        private static func resolveFocusedPane(
            workspaceState: WorkspaceState,
            visibleSections: [WorkspaceContextSection]
        ) -> WorkspacePane? {
            let preferredSection = workspaceState.focusedSection ?? workspaceState.activeSection
            guard let preferredSection else {
                return visibleSections.first?.pane
            }
            return visibleSections.first(where: { $0.section == preferredSection })?.pane
                ?? visibleSections.first?.pane
        }

        private static func makeChatRequestContext(
            notesRuntime: NotesRuntime,
            websitesViewModel: WebsitesViewModel,
            ingestionViewModel: IngestionViewModel,
            weatherViewModel: WeatherViewModel,
            currentLocationViewModel: CurrentLocationViewModel,
            workspaceState: WorkspaceState?
        ) -> ChatRequestContext {
            var openContext: [String: AnyCodable] = [:]
            let visibleSections = orderedWorkspaceContextSections(workspaceState: workspaceState)
            let hasWorkspaceSections = !visibleSections.isEmpty
            let visibleSectionSet = Set(visibleSections.map(\.section))
            if shouldIncludeContext(
                for: .notes,
                hasWorkspaceSections: hasWorkspaceSections,
                visibleSectionSet: visibleSectionSet,
                fallbackSelected: notesRuntime.selectedNoteId != nil
            ) {
                addNoteContext(
                    into: &openContext,
                    notesRuntime: notesRuntime
                )
            }
            if shouldIncludeContext(
                for: .websites,
                hasWorkspaceSections: hasWorkspaceSections,
                visibleSectionSet: visibleSectionSet,
                fallbackSelected: websitesViewModel.selectedWebsiteId != nil
            ) {
                addWebsiteContext(
                    into: &openContext,
                    websitesViewModel: websitesViewModel
                )
            }
            if shouldIncludeContext(
                for: .files,
                hasWorkspaceSections: hasWorkspaceSections,
                visibleSectionSet: visibleSectionSet,
                fallbackSelected: ingestionViewModel.selectedFileId != nil
            ) {
                addFileContext(
                    into: &openContext,
                    ingestionViewModel: ingestionViewModel
                )
            }

            return ChatRequestContext(
                openContext: openContext.isEmpty ? nil : openContext,
                currentLocation: currentLocationViewModel.currentLocationLabel?.trimmedOrNil,
                currentLocationLevels: nil,
                currentWeather: currentWeatherPayload(from: weatherViewModel),
                currentTimezone: TimeZone.current.identifier
            )
        }

        private static func shouldIncludeContext(
            for section: AppSection,
            hasWorkspaceSections: Bool,
            visibleSectionSet: Set<AppSection>,
            fallbackSelected: Bool
        ) -> Bool {
            hasWorkspaceSections
                ? visibleSectionSet.contains(section)
                : fallbackSelected
        }

        private static func addNoteContext(
            into openContext: inout [String: AnyCodable],
            notesRuntime: NotesRuntime
        ) {
            guard let noteContext = notesRuntime.openNoteContext() else { return }
            openContext["note"] = AnyCodable(noteContext)
        }

        private static func addWebsiteContext(
            into openContext: inout [String: AnyCodable],
            websitesViewModel: WebsitesViewModel
        ) {
            guard let selectedWebsiteId = websitesViewModel.selectedWebsiteId,
                  let website = websitesViewModel.active,
                  website.id == selectedWebsiteId else {
                return
            }
            let websiteContext: [String: Any] = [
                "id": website.id,
                "title": website.title,
                "url": website.urlFull ?? website.url,
                "domain": website.domain,
                "content": website.content
            ]
            openContext["website"] = AnyCodable(websiteContext)
        }

        private static func addFileContext(
            into openContext: inout [String: AnyCodable],
            ingestionViewModel: IngestionViewModel
        ) {
            guard let selectedFileId = ingestionViewModel.selectedFileId,
                  let activeMeta = ingestionViewModel.activeMeta,
                  activeMeta.file.id == selectedFileId else {
                return
            }
            var fileContext: [String: Any] = [
                "id": activeMeta.file.id,
                "filename": activeMeta.file.filenameOriginal,
                "mime": activeMeta.file.mimeOriginal
            ]
            if let category = activeMeta.file.category {
                fileContext["category"] = category
            }
            openContext["file"] = AnyCodable(fileContext)
        }

        private static func currentWeatherPayload(
            from weatherViewModel: WeatherViewModel
        ) -> [String: AnyCodable]? {
            guard let weather = weatherViewModel.weather else {
                return nil
            }
            var weatherPayload: [String: AnyCodable] = [
                "temperature_c": AnyCodable(weather.temperatureC),
                "feels_like_c": AnyCodable(weather.feelsLikeC),
                "weather_code": AnyCodable(weather.weatherCode),
                "is_day": AnyCodable(weather.isDay)
            ]
            if let windSpeed = weather.windSpeedKph {
                weatherPayload["wind_speed_kph"] = AnyCodable(windSpeed)
            }
            if let windDirection = weather.windDirectionDegrees {
                weatherPayload["wind_direction_degrees"] = AnyCodable(windDirection)
            }
            if let precipitation = weather.precipitationMm {
                weatherPayload["precipitation_mm"] = AnyCodable(precipitation)
            }
            if let cloudCover = weather.cloudCoverPercent {
                weatherPayload["cloud_cover_percent"] = AnyCodable(cloudCover)
            }
            let daily: [[String: Any]] = weather.daily.map { day in
                var payload: [String: Any] = [
                    "weather_code": day.weatherCode,
                    "temperature_max_c": day.temperatureMaxC,
                    "temperature_min_c": day.temperatureMinC
                ]
                if let precipitationProbability = day.precipitationProbabilityMax {
                    payload["precipitation_probability_max"] = precipitationProbability
                }
                return payload
            }
            weatherPayload["daily"] = AnyCodable(daily)
            return weatherPayload
        }

        // swiftlint:disable:next function_body_length
        static func build(
            container: ServiceContainer,
            core: CoreDependencyBuilder.Output,
            stores: StoreDependencyBuilder.Output,
            widgetDataManager: WidgetDataManager,
            workspaceStateProvider: @escaping () -> WorkspaceState? = { nil }
        ) -> Output {
            let settingsViewModel = makeSettingsViewModel(container: container)
            let notesViewModel = NotesViewModel(
                api: container.notesAPI,
                store: stores.notesStore,
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let notesEditorViewModel = NotesEditorViewModel(
                notesViewModel: notesViewModel,
                draftStorage: core.draftStorage,
                writeQueue: stores.writeQueue,
                networkStatus: core.connectivityMonitor
            )
            let notesRuntime = NotesRuntime(
                viewModel: notesViewModel,
                editorViewModel: notesEditorViewModel
            )
            let ingestionViewModel = IngestionViewModel(
                api: container.ingestionAPI,
                store: stores.ingestionStore,
                temporaryStore: TemporaryFileStore.shared,
                uploadManager: IngestionUploadManager(config: container.apiClient.config),
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let websitesViewModel = WebsitesViewModel(
                api: container.websitesAPI,
                store: stores.websitesStore,
                ingestionStore: stores.ingestionStore,
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let tasksViewModel = TasksViewModel(
                api: container.tasksAPI,
                store: stores.tasksStore,
                widgetDataManager: widgetDataManager,
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let memoriesViewModel = MemoriesViewModel(
                api: container.memoriesAPI,
                cache: container.cacheClient
            )
            let weatherViewModel = WeatherViewModel(api: container.weatherAPI)
            let currentLocationViewModel = CurrentLocationViewModel(
                provider: CoreLocationProvider(),
                labelResolver: CLGeocoderLocationLabelResolver()
            )
            let chatViewModel = ChatViewModel(
                network: ChatNetworkCoordinator(
                    chatAPI: container.chatAPI,
                    conversationsAPI: container.conversationsAPI,
                    ingestionAPI: container.ingestionAPI,
                    streamClient: container.makeChatStreamClient(handler: nil),
                    networkStatus: core.connectivityMonitor
                ),
                storage: ChatStorageCoordinator(
                    cache: container.cacheClient,
                    chatStore: stores.chatStore,
                    notesStore: stores.notesStore,
                    websitesStore: stores.websitesStore,
                    ingestionStore: stores.ingestionStore,
                    scratchpadStore: stores.scratchpadStore
                ),
                ui: ChatUICoordinator(
                    themeManager: core.themeManager,
                    toastCenter: core.toastCenter,
                    onAssistantSettingsUpdated: { settingsViewModel.applyAssistantSettingsUpdate($0) },
                    requestContextProvider: {
                        makeChatRequestContext(
                            notesRuntime: notesRuntime,
                            websitesViewModel: websitesViewModel,
                            ingestionViewModel: ingestionViewModel,
                            weatherViewModel: weatherViewModel,
                            currentLocationViewModel: currentLocationViewModel,
                            workspaceState: workspaceStateProvider()
                        )
                    }
                )
            )

            return Output(
                chatViewModel: chatViewModel,
                notesRuntime: notesRuntime,
                notesViewModel: notesViewModel,
                notesEditorViewModel: notesEditorViewModel,
                ingestionViewModel: ingestionViewModel,
                websitesViewModel: websitesViewModel,
                tasksViewModel: tasksViewModel,
                memoriesViewModel: memoriesViewModel,
                settingsViewModel: settingsViewModel,
                weatherViewModel: weatherViewModel,
                currentLocationViewModel: currentLocationViewModel
            )
        }
    }
}
// swiftlint:enable nesting
