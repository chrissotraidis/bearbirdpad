function(bearbirdpad_module_shell target)
    get_filename_component(root "${BEARBIRDPAD_IOS_DIR}/../.." ABSOLUTE)
    include("${root}/cmake/ModuleIdentity.cmake")
    bearbirdpad_module_identity("${root}" identity)
    target_sources(${target} PRIVATE "${root}/ios/module/game_module_loader.cpp")
    target_include_directories(${target} PRIVATE "${root}/ios/module")
    target_compile_definitions(${target} PRIVATE BEARBIRDPAD_MODULE_SHELL=1 "BEARBIRDPAD_MODULE_ID=\"${identity}\"")
    # Generated code references runtime functions otherwise unseen by the
    # linker's dead-strip pass. Keep one runtime, owned by the executable.
    # The static iOS integration sets OTHER_LDFLAGS directly, which masks
    # CMake target link options in Xcode. Let CMake compose every option here.
    set_property(TARGET ${target} PROPERTY XCODE_ATTRIBUTE_OTHER_LDFLAGS)
    target_link_options(${target} PRIVATE "-ObjC" "-Wl,-export_dynamic"
        "-Wl,-force_load,$<TARGET_FILE:librecomp>" "-Wl,-force_load,$<TARGET_FILE:ultramodern>")
endfunction()
