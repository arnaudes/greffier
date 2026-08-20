import AppKit
import Carbon.HIToolbox
import NoyauCR

/// Démarrer ou arrêter un enregistrement sans chercher l'icône.
///
/// Une réunion commence rarement au moment prévu : elle commence quand
/// quelqu'un dit « bon, on y va ». Il faut alors viser une icône dans la barre
/// de menus, ouvrir un panneau, choisir entre deux boutons — pendant que la
/// conversation, elle, a déjà commencé.
///
/// **⌃⌥⌘R**, choisi parce qu'aucune application courante ne l'emploie et qu'il
/// se tape d'une main.
///
/// L'enregistrement est en visioconférence quand une réunion du calendrier est
/// en cours et qu'elle est en visio, au micro sinon : c'est le choix qu'on
/// aurait fait de toute façon, et il n'y a personne pour le faire à ce
/// moment-là.
@MainActor
final class RaccourciGlobal {
    private var reference: EventHotKeyRef?
    private var gestionnaire: EventHandlerRef?
    private var action: (() -> Void)?

    /// Un identifiant propre à cette application : macOS distingue les
    /// raccourcis par cette signature.
    private let signature = OSType(0x47524646)  // « GRFF »

    func installer(action: @escaping () -> Void) {
        self.action = action
        retirer()

        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let contexte = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, evenement, contexte in
            guard let contexte else { return noErr }
            let moi = Unmanaged<RaccourciGlobal>.fromOpaque(contexte).takeUnretainedValue()
            // Le rappel arrive hors du fil principal : on y revient avant de
            // toucher à l'état de l'application.
            DispatchQueue.main.async { MainActor.assumeIsolated { moi.action?() } }
            return noErr
        }, 1, &type, contexte, &gestionnaire)

        let identifiant = EventHotKeyID(signature: signature, id: 1)
        // ⌃⌥⌘R : contrôle, option, commande et la touche R.
        RegisterEventHotKey(UInt32(kVK_ANSI_R),
                            UInt32(controlKey | optionKey | cmdKey),
                            identifiant, GetApplicationEventTarget(), 0, &reference)
    }

    func retirer() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if let gestionnaire { RemoveEventHandler(gestionnaire) }
        gestionnaire = nil
    }

    /// Comment l'écrire dans l'interface.
    static let libelle = "⌃⌥⌘R"
}
