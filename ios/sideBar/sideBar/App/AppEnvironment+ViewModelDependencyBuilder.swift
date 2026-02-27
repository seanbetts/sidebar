import Foundation
import sideBarShared

// swiftlint:disable nesting
extension AppEnvironment {
    struct ViewModelDependencyBuilder {
        struct Output {
            let chatViewModel: ChatViewModel
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
                currentAuthUserIdProvider: { container.authSession.userId }
            )
        }

        private static func makeChatRequestContext(
            notesViewModel: NotesViewModel,
            notesEditorViewModel: NotesEditorViewModel,
            websitesViewModel: WebsitesViewModel,
            ingestionViewModel: IngestionViewModel,
            weatherViewModel: WeatherViewModel,
            currentLocationViewModel: CurrentLocationViewModel
        ) -> ChatRequestContext {
            var openContext: [String: AnyCodable] = [:]

            if notesViewModel.selectedNoteId != nil, let activeNote = notesViewModel.activeNote {
                let noteContent = notesEditorViewModel.currentMarkdownSnapshot(
                    fallback: activeNote.content
                )
                let noteContext: [String: Any] = [
                    "id": activeNote.id,
                    "title": activeNote.name,
                    "path": activeNote.path,
                    "content": noteContent
                ]
                openContext["note"] = AnyCodable(noteContext)
            }

            if let selectedWebsiteId = websitesViewModel.selectedWebsiteId,
               let website = websitesViewModel.active,
               website.id == selectedWebsiteId {
                let websiteContext: [String: Any] = [
                    "id": website.id,
                    "title": website.title,
                    "url": website.urlFull ?? website.url,
                    "domain": website.domain,
                    "content": website.content
                ]
                openContext["website"] = AnyCodable(websiteContext)
            }

            if let selectedFileId = ingestionViewModel.selectedFileId,
               let activeMeta = ingestionViewModel.activeMeta,
               activeMeta.file.id == selectedFileId {
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

            var currentWeather: [String: AnyCodable]?
            if let weather = weatherViewModel.weather {
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
                currentWeather = weatherPayload
            }

            return ChatRequestContext(
                openContext: openContext.isEmpty ? nil : openContext,
                currentLocation: currentLocationViewModel.currentLocationLabel?.trimmedOrNil,
                currentLocationLevels: nil,
                currentWeather: currentWeather,
                currentTimezone: TimeZone.current.identifier
            )
        }

        // swiftlint:disable:next function_body_length
        static func build(
            container: ServiceContainer,
            core: CoreDependencyBuilder.Output,
            stores: StoreDependencyBuilder.Output
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
                            notesViewModel: notesViewModel,
                            notesEditorViewModel: notesEditorViewModel,
                            websitesViewModel: websitesViewModel,
                            ingestionViewModel: ingestionViewModel,
                            weatherViewModel: weatherViewModel,
                            currentLocationViewModel: currentLocationViewModel
                        )
                    }
                )
            )

            return Output(
                chatViewModel: chatViewModel,
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
