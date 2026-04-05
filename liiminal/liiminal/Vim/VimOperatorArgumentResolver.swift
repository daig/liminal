import Foundation

enum VimOperatorArgumentResolver {
    static func resolvedTarget(
        for argument: VimOperatorArgument,
        in text: NSString,
        from position: Int,
        preferredColumn: Int?,
        markResolver: VimMarkResolver? = nil
    ) -> VimResolvedOperatorTarget? {
        let selection: VimSelectionResult?

        switch argument {
        case .currentLines(let count):
            selection = VimSelectionResolver.currentLineSelectionResult(
                count: max(count ?? 1, 1),
                in: text,
                from: position
            )
        case .motion(let motionArgument):
            selection = VimSelectionResolver.selectionResult(
                for: motionArgument,
                in: text,
                from: position,
                preferredColumn: preferredColumn,
                markResolver: markResolver
            )
        case .object(.text(let objectArgument)):
            selection = VimTextObjectResolver.selectionResult(
                for: objectArgument,
                in: text,
                from: position
            )
        }

        return selection.map(VimResolvedOperatorTarget.text)
    }
}
