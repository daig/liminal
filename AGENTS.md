this is a swift project for macOS developed using XCode.

use your xcode.BuildProject mcp tool to compile, xcode.GetTestList to work with tests etc. use other xcode.* mcp tools as necessary for working with the project, but avoid using xcode.XcodeRead and instead prefer your normal read / edit tools on the underlying files since those are more antural and efficient to you. Only use the xcode mcp tools for things you can't easily do on the command line.

testing notes:

- `liiminalTests` is app-hosted (`TEST_HOST` / `BUNDLE_LOADER`), so do not treat app-facing `@Observable` view models as a stable unit-test seam.
- prefer tests for pure logic layers: parser, document index, link resolution, navigation policy, and other extracted helpers. if behavior currently lives in a view model, extract the decision logic into a pure type first, then test that type.
- do not add tests whose main action is just constructing or tearing down `@Observable` view models unless you explicitly want app-hosted integration coverage.
- when running tests, prefer `xcode.RunSomeTests` / `xcode.RunAllTests` or one serial `xcodebuild test` invocation. do not run multiple test jobs in parallel; it causes deriveddata and logarchive collisions and produces misleading failures.
