//
//  WorkspaceSettingsTab.swift
//  osaurus
//
//  Detail tab a workspace deep link can ask for. Lived inside the deleted
//  `WorkspaceDetailView`; re-homed here because `WorkspacesService.openInSettings`
//  and several call sites still route deep links through it.
//

enum WorkspaceSettingsTab: Hashable {
    case overview
    case members
    case sharedAgents
    case audit
}
