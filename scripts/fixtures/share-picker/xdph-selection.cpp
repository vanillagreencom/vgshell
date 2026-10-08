// Parser excerpt from xdph v1.4.1 src/shared/ScreencopyShared.cpp.
// https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/v1.4.1/src/shared/ScreencopyShared.cpp
// The fixture replaces logging and portal objects with a typed readback.
// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2023, vaxerski. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of the copyright holder nor the names of its contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#include <cstdint>
#include <iostream>
#include <iterator>
#include <string>

int main() {
    const std::string RETVAL{std::istreambuf_iterator<char>(std::cin), {}};
    if (RETVAL.find("[SELECTION]") == std::string::npos)
        return 1;
    try {
        const auto SELECTION = RETVAL.substr(RETVAL.find("[SELECTION]") + 11);
        const auto FLAGS = SELECTION.substr(0, SELECTION.find_first_of('/'));
        const auto SEL = SELECTION.substr(SELECTION.find_first_of('/') + 1);
        bool allowToken = false;
        for (auto& flag : FLAGS) {
            if (flag == 'r')
                allowToken = true;
        }
        if (SEL.find("screen:") == 0) {
            auto output = SEL.substr(7);
            output.pop_back();
            std::cout << "screen\t" << allowToken << "\t" << output << '\n';
        } else if (SEL.find("window:") == 0) {
            uint32_t handleLo = std::stoull(SEL.substr(7));
            std::cout << "window\t" << allowToken << "\t" << handleLo << '\n';
        } else if (SEL.find("region:") == 0) {
            std::string running = SEL;
            running = running.substr(7);
            const auto output = running.substr(0, running.find_first_of('@'));
            running = running.substr(running.find_first_of('@') + 1);
            const auto x = std::stoi(running.substr(0, running.find_first_of(',')));
            running = running.substr(running.find_first_of(',') + 1);
            const auto y = std::stoi(running.substr(0, running.find_first_of(',')));
            running = running.substr(running.find_first_of(',') + 1);
            const auto w = std::stoi(running.substr(0, running.find_first_of(',')));
            running = running.substr(running.find_first_of(',') + 1);
            const auto h = std::stoi(running);
            std::cout << "region\t" << allowToken << "\t" << output << "\t" << x << ',' << y << ',' << w << ',' << h << '\n';
        } else {
            return 1;
        }
    } catch (...) {
        return 1;
    }
}
