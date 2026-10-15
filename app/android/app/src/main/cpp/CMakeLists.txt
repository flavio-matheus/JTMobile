cmake_minimum_required(VERSION 3.22.1)
project(ftx_bridge C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -ffast-math -fvisibility=hidden")

# ft8_lib (MIT) - https://github.com/kgoba/ft8_lib
set(FT8LIB ${CMAKE_CURRENT_SOURCE_DIR}/ft8lib)

add_library(ftx_bridge SHARED
    ftx_bridge.c
    ${FT8LIB}/common/monitor.c
    ${FT8LIB}/fft/kiss_fft.c
    ${FT8LIB}/fft/kiss_fftr.c
    ${FT8LIB}/ft8/constants.c
    ${FT8LIB}/ft8/crc.c
    ${FT8LIB}/ft8/decode.c
    ${FT8LIB}/ft8/encode.c
    ${FT8LIB}/ft8/ldpc.c
    ${FT8LIB}/ft8/message.c
    ${FT8LIB}/ft8/text.c
)

target_include_directories(ftx_bridge PRIVATE ${FT8LIB} ${FT8LIB}/ft8)
target_link_libraries(ftx_bridge m log)
