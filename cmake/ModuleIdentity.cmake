function(bearbirdpad_module_identity root output)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    file(GLOB_RECURSE contract_sources CONFIGURE_DEPENDS
        "${root}/ios/*.h" "${root}/ios/*.hpp" "${root}/ios/*.cpp" "${root}/ios/*.mm"
        "${root}/patches/*.patch" "${root}/cmake/*.cmake" "${root}/cmake/*/CMakeLists.txt" "${root}/cmake/*.manifest")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${contract_sources}
        "${root}/sources.lock.json" "${root}/scripts/module_build.py"
        "${root}/scripts/module-identity.py" "${root}/scripts/build-game-module.py"
        "${root}/scripts/setup-source.py" "${root}/scripts/apply-source-patches.py")
    execute_process(COMMAND "${Python3_EXECUTABLE}" -X utf8 "${root}/scripts/module-identity.py"
        OUTPUT_VARIABLE identity OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    set(${output} "${identity}" PARENT_SCOPE)
endfunction()
