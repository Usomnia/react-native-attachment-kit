module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.rnattachmentkit.RNAttachmentKitPackage;',
        packageInstance: 'new RNAttachmentKitPackage()',
        cmakeListsPath: 'build/generated/source/codegen/jni/CMakeLists.txt',
        libraryName: 'RNAttachmentKitSpec',
      },
      ios: {},
    },
  },
};
