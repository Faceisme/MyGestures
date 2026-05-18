import AppKit
import Foundation
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let inputSubsystemEnabled = true
    private let store = GestureStore.shared
    private let sectionControl = NSSegmentedControl(
        labels: ["鼠标手势功能", "窗口管理相关功能"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let gestureContentView = NSStackView()
    private let windowContentView = NSStackView()
    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let shortcutRecorder = ShortcutRecorderView()
    private let captureView = GestureCaptureView()
    private let moveModifierRecorder = ModifierRecorderView()
    private let resizeModifierRecorder = ModifierRecorderView()
    private let maximizeShortcutRecorder = ShortcutRecorderView()
    private let sampleCountLabel = NSTextField(labelWithString: "样本：0")
    private let statusLabel = NSTextField(labelWithString: "")
    private let gesturesEnabledCheckbox = NSButton(checkboxWithTitle: "启用手势监听", target: nil, action: nil)
    private let showTrailCheckbox = NSButton(checkboxWithTitle: "绘制时显示轨迹", target: nil, action: nil)
    private let showMenuIconCheckbox = NSButton(checkboxWithTitle: "显示菜单栏图标", target: nil, action: nil)
    private let loginItemCheckbox = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    private let gestureTimeoutField = NSTextField()
    private let gestureTimeoutStepper = NSStepper()
    private let targetUnderPointerRadio = NSButton(radioButtonWithTitle: "鼠标指针下方的应用程序和窗口", target: nil, action: nil)
    private let targetActiveWindowRadio = NSButton(radioButtonWithTitle: "活动的应用程序和窗口", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存配置", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除", target: nil, action: nil)
    private let addButton = NSButton(title: "新增", target: nil, action: nil)
    private let undoSampleButton = NSButton(title: "撤销上一个样本", target: nil, action: nil)
    private let clearSamplesButton = NSButton(title: "清空样本", target: nil, action: nil)
    private let importButton = NSButton(title: "导入配置", target: nil, action: nil)
    private let exportButton = NSButton(title: "导出配置", target: nil, action: nil)
    private let clearMoveModifierButton = NSButton(title: "清除", target: nil, action: nil)
    private let clearResizeModifierButton = NSButton(title: "清除", target: nil, action: nil)
    private let clearMaximizeShortcutButton = NSButton(title: "清除", target: nil, action: nil)
    private let maximizeNowButton = NSButton(title: "立即最大化光标下窗口", target: nil, action: nil)
    private var preferredSelectionID: UUID?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MyGestures"
        window.minSize = NSSize(width: 920, height: 560)
        window.center()

        super.init(window: window)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    private func setup() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        configureSectionContainers()
        root.addArrangedSubview(sectionControl)
        root.addArrangedSubview(gestureContentView)
        root.addArrangedSubview(windowContentView)
        root.addArrangedSubview(statusLabel)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)

        sectionControl.selectedSegment = 0
        sectionControl.target = self
        sectionControl.action = #selector(switchSettingsSection)
        gesturesEnabledCheckbox.target = self
        gesturesEnabledCheckbox.action = #selector(toggleGesturesEnabled)
        gesturesEnabledCheckbox.isEnabled = inputSubsystemEnabled
        showTrailCheckbox.target = self
        showTrailCheckbox.action = #selector(toggleShowTrail)
        showMenuIconCheckbox.target = self
        showMenuIconCheckbox.action = #selector(toggleMenuIcon)
        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem)
        gestureTimeoutField.delegate = self
        gestureTimeoutField.alignment = .right
        gestureTimeoutField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        gestureTimeoutField.action = #selector(commitGestureTimeoutFromField)
        gestureTimeoutField.target = self
        gestureTimeoutStepper.minValue = 0.5
        gestureTimeoutStepper.maxValue = 10
        gestureTimeoutStepper.increment = 0.5
        gestureTimeoutStepper.target = self
        gestureTimeoutStepper.action = #selector(gestureTimeoutStepperChanged)
        targetUnderPointerRadio.target = self
        targetUnderPointerRadio.action = #selector(selectWindowUnderPointerTarget)
        targetActiveWindowRadio.target = self
        targetActiveWindowRadio.action = #selector(selectActiveWindowTarget)

        addButton.target = self
        addButton.action = #selector(addGesture)
        deleteButton.target = self
        deleteButton.action = #selector(deleteGesture)
        saveButton.target = self
        saveButton.action = #selector(saveConfiguration)
        undoSampleButton.target = self
        undoSampleButton.action = #selector(undoLastSample)
        clearSamplesButton.target = self
        clearSamplesButton.action = #selector(clearSamples)
        importButton.target = self
        importButton.action = #selector(importConfiguration)
        exportButton.target = self
        exportButton.action = #selector(exportConfiguration)
        clearMoveModifierButton.target = self
        clearMoveModifierButton.action = #selector(clearMoveModifier)
        clearResizeModifierButton.target = self
        clearResizeModifierButton.action = #selector(clearResizeModifier)
        clearMaximizeShortcutButton.target = self
        clearMaximizeShortcutButton.action = #selector(clearMaximizeShortcut)
        maximizeNowButton.target = self
        maximizeNowButton.action = #selector(maximizeWindowUnderPointerNow)
        configureControlAppearance()

        nameField.delegate = self
        shortcutRecorder.onShortcutChanged = { [weak self] shortcut in
            self?.updateSelectedGesture { gesture in
                gesture.shortcut = shortcut
            }
        }
        captureView.onStrokeFinished = { [weak self] points in
            self?.appendTemplate(points)
        }
        moveModifierRecorder.onModifierFlagsChanged = { [weak self] rawValue in
            self?.store.updatePreferences { preferences in
                preferences.windowMoveModifierFlags = rawValue
            }
        }
        resizeModifierRecorder.onModifierFlagsChanged = { [weak self] rawValue in
            self?.store.updatePreferences { preferences in
                preferences.windowResizeModifierFlags = rawValue
            }
        }
        maximizeShortcutRecorder.onShortcutChanged = { [weak self] shortcut in
            self?.store.updatePreferences { preferences in
                preferences.windowMaximizeShortcut = shortcut
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: .gestureStoreDidChange,
            object: store
        )

        reload()
    }

    private func configureSectionContainers() {
        gestureContentView.orientation = .vertical
        gestureContentView.spacing = 18
        gestureContentView.addArrangedSubview(makePreferenceRow())
        gestureContentView.addArrangedSubview(makeMainRow())

        windowContentView.orientation = .vertical
        windowContentView.spacing = 18
        windowContentView.addArrangedSubview(makeWindowManagementContent())
        windowContentView.isHidden = true
    }

    private func makePreferenceRow() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .top
        container.spacing = 14
        container.distribution = .fill

        let general = NSStackView()
        general.orientation = .vertical
        general.alignment = .leading
        general.spacing = 8

        let generalFirstRow = NSStackView()
        generalFirstRow.orientation = .horizontal
        generalFirstRow.alignment = .centerY
        generalFirstRow.spacing = 14

        let generalSecondRow = NSStackView()
        generalSecondRow.orientation = .horizontal
        generalSecondRow.alignment = .centerY
        generalSecondRow.spacing = 14

        let generalThirdRow = NSStackView()
        generalThirdRow.orientation = .horizontal
        generalThirdRow.alignment = .centerY
        generalThirdRow.spacing = 10

        let permissionButton = NSButton(title: "打开权限设置", target: self, action: #selector(openPermissions))
        permissionButton.bezelStyle = .rounded

        generalFirstRow.addArrangedSubview(gesturesEnabledCheckbox)
        generalFirstRow.addArrangedSubview(loginItemCheckbox)
        generalFirstRow.addArrangedSubview(showMenuIconCheckbox)

        generalSecondRow.addArrangedSubview(showTrailCheckbox)
        generalSecondRow.addArrangedSubview(makeGestureTimeoutControl())
        generalSecondRow.addArrangedSubview(permissionButton)

        generalThirdRow.addArrangedSubview(importButton)
        generalThirdRow.addArrangedSubview(exportButton)
        generalThirdRow.addArrangedSubview(saveButton)

        general.addArrangedSubview(generalFirstRow)
        general.addArrangedSubview(generalSecondRow)
        general.addArrangedSubview(generalThirdRow)

        let targetStack = NSStackView()
        targetStack.orientation = .vertical
        targetStack.alignment = .leading
        targetStack.spacing = 8
        targetUnderPointerRadio.toolTip = "切换到鼠标指针下方的窗口，然后执行手势快捷键。"
        targetActiveWindowRadio.toolTip = "始终作用于手势开始时的前台应用，不受鼠标位置影响。"
        targetStack.addArrangedSubview(targetUnderPointerRadio)
        targetStack.addArrangedSubview(targetActiveWindowRadio)

        let generalSection = makeSection(title: "通用", content: general)
        let targetSection = makeSection(title: "手势作用目标", content: targetStack)

        container.addArrangedSubview(generalSection)
        container.addArrangedSubview(targetSection)

        NSLayoutConstraint.activate([
            generalSection.widthAnchor.constraint(greaterThanOrEqualToConstant: 580),
            targetSection.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])

        return container
    }

    private func makeMainRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 18
        row.distribution = .fill

        let listPanel = makeSection(title: "手势列表", content: makeListPanel())
        let editorPanel = makeSection(title: "编辑手势", content: makeEditorPanel())

        row.addArrangedSubview(listPanel)
        row.addArrangedSubview(editorPanel)

        NSLayoutConstraint.activate([
            listPanel.widthAnchor.constraint(equalToConstant: 350),
            editorPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 520)
        ])

        return row
    }

    private func makeWindowManagementContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18

        let description = NSTextField(labelWithString: "窗口操作默认作用于鼠标光标下方的窗口，即使该窗口不是当前前台窗口。")
        description.textColor = .secondaryLabelColor
        description.font = .systemFont(ofSize: 12)
        description.maximumNumberOfLines = 2

        let moveResizeStack = NSStackView()
        moveResizeStack.orientation = .vertical
        moveResizeStack.alignment = .leading
        moveResizeStack.spacing = 10
        moveResizeStack.addArrangedSubview(description)
        moveResizeStack.addArrangedSubview(makeModifierRow(title: "移动窗口修饰键", recorder: moveModifierRecorder, clearButton: clearMoveModifierButton))
        moveResizeStack.addArrangedSubview(makeModifierRow(title: "缩放窗口修饰键", recorder: resizeModifierRecorder, clearButton: clearResizeModifierButton))

        let hint = NSTextField(labelWithString: "按住已设置的修饰键并移动鼠标：移动窗口；按住缩放修饰键并移动鼠标：按光标所在边角缩放窗口。")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        hint.maximumNumberOfLines = 2
        moveResizeStack.addArrangedSubview(hint)

        let maximizeStack = NSStackView()
        maximizeStack.orientation = .vertical
        maximizeStack.alignment = .leading
        maximizeStack.spacing = 10
        maximizeStack.addArrangedSubview(makeShortcutRow(title: "最大化光标下窗口", recorder: maximizeShortcutRecorder, clearButton: clearMaximizeShortcutButton))
        maximizeStack.addArrangedSubview(maximizeNowButton)

        let moveResizeSection = makeSection(title: "移动和缩放", content: moveResizeStack)
        let maximizeSection = makeSection(title: "窗口管理", content: maximizeStack)

        stack.addArrangedSubview(moveResizeSection)
        stack.addArrangedSubview(maximizeSection)
        stack.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            moveResizeSection.widthAnchor.constraint(greaterThanOrEqualToConstant: 620),
            maximizeSection.widthAnchor.constraint(greaterThanOrEqualToConstant: 620),
            moveModifierRecorder.widthAnchor.constraint(equalToConstant: 240),
            resizeModifierRecorder.widthAnchor.constraint(equalToConstant: 240),
            maximizeShortcutRecorder.widthAnchor.constraint(equalToConstant: 240),
            moveModifierRecorder.heightAnchor.constraint(equalToConstant: 38),
            resizeModifierRecorder.heightAnchor.constraint(equalToConstant: 38),
            maximizeShortcutRecorder.heightAnchor.constraint(equalToConstant: 38)
        ])

        return stack
    }

    private func makeModifierRow(title: String, recorder: ModifierRecorderView, clearButton: NSButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(recorder)
        row.addArrangedSubview(clearButton)
        return row
    }

    private func makeShortcutRow(title: String, recorder: ShortcutRecorderView, clearButton: NSButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(recorder)
        row.addArrangedSubview(clearButton)
        return row
    }

    private func makeListPanel() -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical
        panel.spacing = 10

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        header.addArrangedSubview(NSView())
        header.addArrangedSubview(addButton)
        header.addArrangedSubview(deleteButton)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "名称"
        nameColumn.width = 190

        let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutColumn.title = "快捷键"
        shortcutColumn.width = 120

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(shortcutColumn)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = false
        tableView.rowHeight = 32
        tableView.style = .inset
        tableView.gridStyleMask = []
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        panel.addArrangedSubview(header)
        panel.addArrangedSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])

        return panel
    }

    private func makeEditorPanel() -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 12

        nameField.placeholderString = "输入手势名称"
        nameField.font = .systemFont(ofSize: 14)
        nameField.cell?.usesSingleLineMode = true
        nameField.lineBreakMode = .byTruncatingTail
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let shortcutLabel = NSTextField(labelWithString: "快捷键")
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let sampleLabel = NSTextField(labelWithString: "手势样本")
        sampleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let hintLabel = NSTextField(labelWithString: "建议：同一个手势录制 2-3 个样本，识别会更稳。")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.maximumNumberOfLines = 2

        let sampleActions = NSStackView()
        sampleActions.orientation = .horizontal
        sampleActions.alignment = .centerY
        sampleActions.spacing = 8
        sampleActions.addArrangedSubview(sampleCountLabel)
        sampleActions.addArrangedSubview(undoSampleButton)
        sampleActions.addArrangedSubview(clearSamplesButton)
        sampleActions.addArrangedSubview(NSView())

        panel.addArrangedSubview(labeledView(title: "名称", view: nameField))
        panel.addArrangedSubview(shortcutLabel)
        panel.addArrangedSubview(shortcutRecorder)
        panel.addArrangedSubview(sampleLabel)
        panel.addArrangedSubview(captureView)
        panel.addArrangedSubview(sampleActions)
        panel.addArrangedSubview(hintLabel)

        NSLayoutConstraint.activate([
            nameField.heightAnchor.constraint(equalToConstant: 28),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            shortcutRecorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            shortcutRecorder.heightAnchor.constraint(equalToConstant: 44),
            captureView.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            captureView.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            saveButton.widthAnchor.constraint(equalToConstant: 96),
            undoSampleButton.widthAnchor.constraint(equalToConstant: 120),
            clearSamplesButton.widthAnchor.constraint(equalToConstant: 90)
        ])

        return panel
    }

    private func makeGestureTimeoutControl() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5

        let label = NSTextField(labelWithString: "手势最长")
        label.font = .systemFont(ofSize: 13)
        let unit = NSTextField(labelWithString: "秒")
        unit.font = .systemFont(ofSize: 13)

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(gestureTimeoutField)
        stack.addArrangedSubview(gestureTimeoutStepper)
        stack.addArrangedSubview(unit)

        NSLayoutConstraint.activate([
            gestureTimeoutField.widthAnchor.constraint(equalToConstant: 48)
        ])

        return stack
    }

    private func labeledView(title: String, view: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(view)
        return stack
    }

    private func makeSection(title: String, content: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .primary
        box.contentViewMargins = NSSize(width: 14, height: 12)
        box.contentView = content
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func configureControlAppearance() {
        for button in [
            saveButton,
            deleteButton,
            addButton,
            undoSampleButton,
            clearSamplesButton,
            importButton,
            exportButton,
            clearMoveModifierButton,
            clearResizeModifierButton,
            clearMaximizeShortcutButton,
            maximizeNowButton
        ] {
            button.bezelStyle = .rounded
        }
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新增")
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        saveButton.keyEquivalent = "\r"
    }

    private func reload() {
        let selectedID = preferredSelectionID ?? selectedGesture?.id
        preferredSelectionID = nil

        gesturesEnabledCheckbox.state = store.preferences.gesturesEnabled ? .on : .off
        showTrailCheckbox.state = store.preferences.showTrail ? .on : .off
        showMenuIconCheckbox.state = store.preferences.showMenuBarIcon ? .on : .off
        updateGestureTimeoutControls()
        targetUnderPointerRadio.state = store.preferences.gestureTargetPolicy == .windowUnderPointer ? .on : .off
        targetActiveWindowRadio.state = store.preferences.gestureTargetPolicy == .activeWindow ? .on : .off
        moveModifierRecorder.modifierFlagsRawValue = store.preferences.windowMoveModifierFlags
        resizeModifierRecorder.modifierFlagsRawValue = store.preferences.windowResizeModifierFlags
        maximizeShortcutRecorder.shortcut = store.preferences.windowMaximizeShortcut
        loginItemCheckbox.state = LoginItemManager.isEnabled ? .on : .off
        statusLabel.stringValue = PermissionManager.isAccessibilityTrusted
            ? "辅助功能权限已开启。"
            : "辅助功能权限尚未开启。"

        tableView.reloadData()

        if store.gestures.isEmpty {
            clearEditor()
        } else {
            let row = selectedID.flatMap { id in
                store.gestures.firstIndex { $0.id == id }
            } ?? max(tableView.selectedRow, 0)
            let clampedRow = min(row, store.gestures.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: clampedRow), byExtendingSelection: false)
            updateEditor()
        }
    }

    private func updateEditor() {
        guard let gesture = selectedGesture else {
            clearEditor()
            return
        }

        nameField.stringValue = gesture.name
        shortcutRecorder.shortcut = gesture.shortcut
        captureView.showTemplates(gesture.templates)
        sampleCountLabel.stringValue = "样本：\(gesture.templates.count)"
        setEditorEnabled(true)
    }

    private func clearEditor() {
        nameField.stringValue = ""
        shortcutRecorder.shortcut = nil
        captureView.showTemplates([])
        sampleCountLabel.stringValue = "样本：0"
        setEditorEnabled(false)
    }

    private func setEditorEnabled(_ enabled: Bool) {
        nameField.isEnabled = enabled
        shortcutRecorder.isHidden = !enabled
        captureView.isHidden = !enabled
        deleteButton.isEnabled = enabled
        undoSampleButton.isEnabled = enabled && (selectedGesture?.templates.isEmpty == false)
        clearSamplesButton.isEnabled = enabled && (selectedGesture?.templates.isEmpty == false)
    }

    private var selectedGesture: GestureCommand? {
        let row = tableView.selectedRow
        guard row >= 0, row < store.gestures.count else {
            return nil
        }
        return store.gestures[row]
    }

    private func updateSelectedGesture(_ update: (inout GestureCommand) -> Void) {
        let row = tableView.selectedRow
        guard row >= 0, row < store.gestures.count else {
            return
        }

        preferredSelectionID = store.gestures[row].id
        store.updateGestures { gestures in
            update(&gestures[row])
        }
    }

    private func appendTemplate(_ points: [CGPoint]) {
        updateSelectedGesture { gesture in
            gesture.templates.append(points.map(StrokePoint.init))
        }
    }

    @objc private func storeDidChange() {
        reload()
    }

    @objc private func toggleGesturesEnabled() {
        guard inputSubsystemEnabled else {
            gesturesEnabledCheckbox.state = .off
            statusLabel.stringValue = "当前版本已禁用输入监听，用于排查键鼠稳定性。"
            return
        }

        store.updatePreferences { preferences in
            preferences.gesturesEnabled = gesturesEnabledCheckbox.state == .on
        }
    }

    @objc private func toggleShowTrail() {
        store.updatePreferences { preferences in
            preferences.showTrail = showTrailCheckbox.state == .on
        }
    }

    @objc private func toggleMenuIcon() {
        store.updatePreferences { preferences in
            preferences.showMenuBarIcon = showMenuIconCheckbox.state == .on
        }
    }

    @objc private func gestureTimeoutStepperChanged() {
        commitGestureTimeout(gestureTimeoutStepper.doubleValue)
    }

    @objc private func commitGestureTimeoutFromField() {
        commitGestureTimeout(Double(gestureTimeoutField.stringValue) ?? store.preferences.gestureTimeoutSeconds)
    }

    private func commitGestureTimeout(_ value: Double) {
        let clampedValue = min(max(value, gestureTimeoutStepper.minValue), gestureTimeoutStepper.maxValue)
        store.updatePreferences { preferences in
            preferences.gestureTimeoutSeconds = clampedValue
        }
        updateGestureTimeoutControls()
    }

    private func updateGestureTimeoutControls() {
        let value = min(max(store.preferences.gestureTimeoutSeconds, gestureTimeoutStepper.minValue), gestureTimeoutStepper.maxValue)
        gestureTimeoutStepper.doubleValue = value
        gestureTimeoutField.stringValue = String(format: "%.1f", value)
    }

    @objc private func selectWindowUnderPointerTarget() {
        store.updatePreferences { preferences in
            preferences.gestureTargetPolicy = .windowUnderPointer
        }
    }

    @objc private func selectActiveWindowTarget() {
        store.updatePreferences { preferences in
            preferences.gestureTargetPolicy = .activeWindow
        }
    }

    @objc private func switchSettingsSection() {
        let showingWindows = sectionControl.selectedSegment == 1
        gestureContentView.isHidden = showingWindows
        windowContentView.isHidden = !showingWindows
    }

    @objc private func clearMoveModifier() {
        store.updatePreferences { preferences in
            preferences.windowMoveModifierFlags = 0
        }
    }

    @objc private func clearResizeModifier() {
        store.updatePreferences { preferences in
            preferences.windowResizeModifierFlags = 0
        }
    }

    @objc private func clearMaximizeShortcut() {
        store.updatePreferences { preferences in
            preferences.windowMaximizeShortcut = nil
        }
    }

    @objc private func maximizeWindowUnderPointerNow() {
        let point = CGEvent(source: nil)?.location ?? .zero
        DispatchQueue.global(qos: .userInteractive).async {
            GestureTargetController.maximizeWindowUnderPointer(at: point)
        }
    }

    @objc private func toggleLoginItem() {
        do {
            try LoginItemManager.setEnabled(loginItemCheckbox.state == .on)
            statusLabel.stringValue = "开机启动设置已更新。"
        } catch {
            statusLabel.stringValue = "无法更新开机启动：\(error.localizedDescription)"
            loginItemCheckbox.state = LoginItemManager.isEnabled ? .on : .off
        }
    }

    @objc private func openPermissions() {
        PermissionManager.openPrivacySettings()
        reload()
    }

    @objc private func exportConfiguration() {
        saveCurrentEditor(showStatus: false)

        let panel = NSSavePanel()
        panel.title = "导出 MyGestures 配置"
        panel.nameFieldStringValue = "MyGestures-Backup.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try store.exportBackupData()
            try data.write(to: url, options: .atomic)
            statusLabel.stringValue = "配置已导出：\(url.lastPathComponent)"
        } catch {
            showError(title: "导出失败", message: error.localizedDescription)
        }
    }

    @objc private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "导入 MyGestures 配置"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let confirmation = NSAlert()
        confirmation.messageText = "导入配置会覆盖当前手势"
        confirmation.informativeText = "建议先导出当前配置作为备份。"
        confirmation.alertStyle = .warning
        confirmation.addButton(withTitle: "导入")
        confirmation.addButton(withTitle: "取消")

        guard confirmation.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            try store.importBackupData(data)
            loginItemCheckbox.state = LoginItemManager.isEnabled ? .on : .off
            statusLabel.stringValue = "配置已导入：\(url.lastPathComponent)"
        } catch {
            reload()
            showError(title: "导入失败", message: error.localizedDescription)
        }
    }

    @objc private func addGesture() {
        let newGesture = GestureCommand(name: "新手势", templates: [], shortcut: nil)
        preferredSelectionID = newGesture.id

        store.updateGestures { gestures in
            gestures.append(newGesture)
        }

        selectGesture(with: newGesture.id)
        nameField.becomeFirstResponder()
    }

    @objc private func deleteGesture() {
        let row = tableView.selectedRow
        guard row >= 0, row < store.gestures.count else {
            return
        }

        if store.gestures.count > 1 {
            let nextRow = min(row, store.gestures.count - 2)
            preferredSelectionID = store.gestures[nextRow == row ? row + 1 : nextRow].id
        }

        store.updateGestures { gestures in
            gestures.remove(at: row)
        }

        if !store.gestures.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: min(row, store.gestures.count - 1)), byExtendingSelection: false)
        }
    }

    @objc private func undoLastSample() {
        updateSelectedGesture { gesture in
            if !gesture.templates.isEmpty {
                gesture.templates.removeLast()
            }
        }
        captureView.clear()
    }

    @objc private func clearSamples() {
        updateSelectedGesture { gesture in
            gesture.templates.removeAll()
        }
        captureView.clear()
    }

    @objc private func saveConfiguration() {
        saveCurrentEditor(showStatus: true)
    }

    private func saveCurrentEditor(showStatus: Bool) {
        updateSelectedGesture { gesture in
            gesture.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "未命名"
                : nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let shortcut = shortcutRecorder.shortcut {
                gesture.shortcut = shortcut
            }
        }

        if showStatus {
            statusLabel.stringValue = "配置已保存。"
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.gestures.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < store.gestures.count else {
            return nil
        }

        let gesture = store.gestures[row]
        let identifier = tableColumn?.identifier.rawValue == "shortcut"
            ? NSUserInterfaceItemIdentifier("ShortcutCell")
            : NSUserInterfaceItemIdentifier("NameCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? CenteredTableCellView
            ?? CenteredTableCellView(identifier: identifier)

        switch tableColumn?.identifier.rawValue {
        case "shortcut":
            cell.stringValue = gesture.shortcut?.displayName ?? "未设置"
            cell.textAlignment = .left
        default:
            cell.stringValue = gesture.name
            cell.textAlignment = .left
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateEditor()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField, textField === gestureTimeoutField {
            commitGestureTimeoutFromField()
            return
        }
        saveCurrentEditor(showStatus: false)
    }

    private func selectGesture(with id: UUID) {
        guard let row = store.gestures.firstIndex(where: { $0.id == id }) else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        updateEditor()
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

private final class CenteredTableCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    var stringValue: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    var textAlignment: NSTextAlignment {
        get { label.alignment }
        set { label.alignment = newValue }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            label.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
        }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard label.superview == nil else {
            return
        }

        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
