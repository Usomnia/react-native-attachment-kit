cmake_minimum_required(VERSION 3.13.4 FATAL_ERROR)
set(CMAKE_VERBOSE_MAKEFILE ON)

project(react_codegen_RNAttachmentKitSpec)

# Android 15+ 16KB 페이지 기기 지원 (Google Play: targetSdk 35+ 업데이트 필수). NDK r27 이하는 기본이 4KB 정렬이라 명시
string(APPEND CMAKE_SHARED_LINKER_FLAGS " -Wl,-z,max-page-size=16384")

set(GENERATED_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/generated/source/codegen/jni")

if(NOT COMMAND target_compile_reactnative_options)
    macro(target_compile_reactnative_options target scope)
        # Standalone build fail 방지용 더미 (RN 전역 룰이 없을 땐 무시)
    endmacro()
endif()
if(EXISTS "${GENERATED_SRC_DIR}/CMakeLists.txt")
    message(STATUS "RNAttachmentKit: Found codegen CMakeLists.txt at ${GENERATED_SRC_DIR}")
    add_subdirectory("${GENERATED_SRC_DIR}" "codegen_RNAttachmentKitSpec")
    
    # React Native 0.74 Codegen 버그(타겟명이 AppSpecs로 고정되는 문제) 우회
    if(TARGET react_codegen_AppSpecs AND NOT TARGET react_codegen_RNAttachmentKitSpec)
        message(STATUS "RNAttachmentKit: Bridging react_codegen_AppSpecs -> react_codegen_RNAttachmentKitSpec")
        add_library(react_codegen_RNAttachmentKitSpec INTERFACE)
        target_link_libraries(react_codegen_RNAttachmentKitSpec INTERFACE react_codegen_AppSpecs)
    endif()
else()
    message(WARNING "RNAttachmentKit: Codegen CMakeLists.txt NOT FOUND! Dummy library will be used to prevent crash.")
    # 앱의 링킹 오류를 방지하기 위해 더미 타겟 생성
    add_library(react_codegen_RNAttachmentKitSpec SHARED)
    
    # 더미 소스 생성
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/dummy.cpp" "void dummy_RNAttachmentKitSpec() {}")
    target_sources(react_codegen_RNAttachmentKitSpec PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/dummy.cpp")
endif()
