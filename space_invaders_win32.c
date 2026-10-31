// Space Invaders mini - C17 / Win32 (Windows 11 x64)
// Port of space_invaders_uefi.asm (NASM / UEFI) with the same game rules,
// pixel art, coordinates, palette, 5x7 font, and 640x480 logical canvas.
// The UEFI GOP framebuffer and keyboard are replaced by Win32 + GDI.
//
// Build from a VS 2022 x64 Developer PowerShell:
//   clang-cl /nologo /std:c17 /W4 /O2 space_invaders_win32.c /Fe:space_invaders.exe /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib
//
// No third-party dependencies or assets.
// This file was made with AI, the real one is the assembly file

#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdint.h>

#define WIDTH  640
#define HEIGHT 480

#define C_BG    0x0009101Eu
#define C_FRAME 0x00304A6Au
#define C_DIM   0x00677B99u
#define C_WHITE 0x00D7E8FFu
#define C_BLUE  0x003B81F6u
#define C_CYAN  0x009BD1FFu
#define C_PINK  0x00FD79B8u
#define C_GREEN 0x0073EDB0u
#define C_RED   0x00F26976u
#define C_DARK  0x00142135u

// Top-down 32-bit DIB: a DWORD 0x00RRGGBB has bytes BB GG RR 00.
// This is equivalent to UEFI GOP PixelBlueGreenRedReserved8BitPerColor.
static uint32_t framebuffer[WIDTH * HEIGHT];
static const BITMAPINFO bitmap_info = {
    .bmiHeader = {
        .biSize = sizeof(BITMAPINFOHEADER),
        .biWidth = WIDTH,
        .biHeight = -HEIGHT,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = BI_RGB,
    },
};

static const int stars[24][2] = {
    {28, 78}, {71, 129}, {137, 70}, {203, 164},
    {264, 80}, {334, 135}, {405, 94}, {481, 148},
    {551, 78}, {603, 194}, {35, 247}, {89, 359},
    {159, 290}, {219, 398}, {283, 347}, {357, 371},
    {429, 302}, {513, 411}, {586, 334}, {618, 394},
    {59, 411}, {187, 221}, {388, 229}, {572, 257},
};

// Original 5x7 glyphs, unchanged: 0-9 followed by A-Z.
static const uint8_t font[36][7] = {
    {0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E}, // 0
    {0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E}, // 1
    {0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F}, // 2
    {0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E}, // 3
    {0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02}, // 4
    {0x1F, 0x10, 0x10, 0x1E, 0x01, 0x01, 0x1E}, // 5
    {0x0E, 0x10, 0x10, 0x1E, 0x11, 0x11, 0x0E}, // 6
    {0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08}, // 7
    {0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E}, // 8
    {0x0E, 0x11, 0x11, 0x0F, 0x01, 0x01, 0x0E}, // 9
    {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // A
    {0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E}, // B
    {0x0F, 0x10, 0x10, 0x10, 0x10, 0x10, 0x0F}, // C
    {0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E}, // D
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F}, // E
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10}, // F
    {0x0F, 0x10, 0x10, 0x17, 0x11, 0x11, 0x0F}, // G
    {0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // H
    {0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E}, // I
    {0x07, 0x02, 0x02, 0x02, 0x12, 0x12, 0x0C}, // J
    {0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11}, // K
    {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F}, // L
    {0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11}, // M
    {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11}, // N
    {0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // O
    {0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10}, // P
    {0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D}, // Q
    {0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11}, // R
    {0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E}, // S
    {0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04}, // T
    {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // U
    {0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04}, // V
    {0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A}, // W
    {0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11}, // X
    {0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04}, // Y
    {0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F}, // Z
};

// Original .bss variables; initialized by reset_game() as in the ASM.
static int32_t player_x, enemy_x, enemy_y, enemy_dir;
static uint32_t alive_mask, score, frame_counter;
static int32_t lives, bullet_x, bullet_y, eshot_x, eshot_y;
static uint8_t bullet_active, eshot_active, game_state, quit_game;

// Equivalent to draw_rect in the assembly. All game rectangles fit the canvas.
static void draw_rect(int x, int y, int w, int h, uint32_t rgb)
{
    for (int row = 0; row < h; ++row) {
        uint32_t *dst = &framebuffer[(y + row) * WIDTH + x];
        for (int col = 0; col < w; ++col)
            dst[col] = rgb;
    }
}

// Equivalent to draw_text: each original font pixel becomes a 2x2 square;
// every glyph advances the cursor by 12 pixels, including spaces.
static void draw_text(const char *text, int x, int y, uint32_t color)
{
    for (; *text != '\0'; ++text, x += 12) {
        const unsigned char ch = (unsigned char)*text;
        int index;

        if (ch >= '0' && ch <= '9')
            index = ch - '0';
        else if (ch >= 'A' && ch <= 'Z')
            index = ch - 'A' + 10;
        else
            continue;

        for (int row = 0; row < 7; ++row)
            for (int col = 0; col < 5; ++col)
                if ((font[index][row] & (1u << (4 - col))) != 0)
                    draw_rect(x + col * 2, y + row * 2, 2, 2, color);
    }
}

static void reset_game(void)
{
    player_x = 298;
    enemy_x = 88;
    enemy_y = 85;
    enemy_dir = 1;
    alive_mask = 0x3FFFFu;
    score = 0;
    lives = 3;
    frame_counter = 0;
    bullet_active = 0;
    eshot_active = 0;
    game_state = 0;  // 0: playing, 1: victory, 2: defeat
}

// Win32 virtual-key events replace the UEFI ReadKeyStroke/ScanCode events.
static void handle_key(WPARAM key)
{
    if (key == VK_ESCAPE) {
        quit_game = 1;
        return;
    }

    if (game_state != 0) {
        if (key == 'R')
            reset_game();
        return;
    }

    switch (key) {
    case VK_LEFT:
    case 'A':
        player_x -= 18;
        if (player_x < 8)
            player_x = 8;
        break;

    case VK_RIGHT:
    case 'D':
        player_x += 18;
        if (player_x > 588)
            player_x = 588;
        break;

    case VK_SPACE:
        if (!bullet_active) {
            bullet_x = player_x + 20;
            bullet_y = 406;
            bullet_active = 1;
        }
        break;
    }
}

// Straight translation of update_game, including collision bounding boxes.
static void update_game(void)
{
    ++frame_counter;

    if (frame_counter % 7u == 0) {
        enemy_x += enemy_dir * 5;

        if (enemy_x <= 30) {
            enemy_dir = 1;
        } else if (enemy_x >= 242) {
            enemy_dir = -1;
        } else {
            goto bullet_step;
        }

        enemy_y += 15;
        if (enemy_y >= 284) {
            game_state = 2;
            return;
        }
    }

bullet_step:
    if (bullet_active) {
        bullet_y -= 10;

        if (bullet_y < 50) {
            bullet_active = 0;
        } else {
            for (unsigned i = 0; i < 18; ++i) {
                const uint32_t bit = 1u << i;
                if ((alive_mask & bit) == 0)
                    continue;

                const int x = enemy_x + (int)(i % 6u) * 70;
                const int y = enemy_y + (int)(i / 6u) * 48;

                // [bullet_x, bullet_x+4) x [bullet_y, bullet_y+12)
                // versus [x, x+32) x [y, y+22).
                if (bullet_x + 4 > x && bullet_x < x + 32 &&
                    bullet_y + 12 > y && bullet_y < y + 22) {
                    alive_mask &= ~bit;
                    ++score;
                    bullet_active = 0;

                    if (alive_mask == 0) {
                        game_state = 1;
                        return;
                    }
                    break;
                }
            }
        }
    }

    if (!eshot_active) {
        if (frame_counter % 53u != 0)
            return;

        unsigned shooter = frame_counter % 18u;
        for (unsigned attempts = 0; attempts < 18; ++attempts) {
            if ((alive_mask & (1u << shooter)) != 0) {
                eshot_x = enemy_x + (int)(shooter % 6u) * 70 + 14;
                eshot_y = enemy_y + (int)(shooter / 6u) * 48 + 22;
                eshot_active = 1;
                return;
            }
            shooter = (shooter + 1u) % 18u;
        }
        return;
    }

    eshot_y += 6;
    if (eshot_y >= 470) {
        eshot_active = 0;
        return;
    }
    if (eshot_y < 418 || eshot_y >= 444)
        return;

    if (eshot_x + 5 > player_x && eshot_x < player_x + 44) {
        --lives;
        eshot_active = 0;
        if (lives == 0)
            game_state = 2;
    }
}

// Pixel-for-pixel equivalent of the drawing instructions in render_game.
static void render_game(void)
{
    draw_rect(0, 0, WIDTH, HEIGHT, C_BG);

    for (unsigned i = 0; i < 24; ++i)
        draw_rect(stars[i][0], stars[i][1], 2, 2, C_DIM);

    draw_rect(8,   8, 624,   2, C_FRAME);
    draw_rect(8,   8,   2, 464, C_FRAME);
    draw_rect(630, 8,   2, 464, C_FRAME);
    draw_rect(8, 471, 624,   2, C_FRAME);
    draw_rect(8,  51, 624,   2, C_FRAME);
    draw_rect(8, 451, 624,   2, C_FRAME);

    draw_text("SCORE", 20, 19, C_CYAN);
    char score_digits[3] = {
        (char)('0' + score / 10u),
        (char)('0' + score % 10u),
        '\0'
    };
    draw_text(score_digits, 98, 19, C_WHITE);
    draw_text("SPACE INVADERS", 225, 19, C_BLUE);
    draw_text("LIVES", 491, 19, C_CYAN);

    for (int i = 0; i < lives; ++i)
        draw_rect(568 + i * 19, 22, 13, 11, C_GREEN);

    for (unsigned i = 0; i < 18; ++i) {
        if ((alive_mask & (1u << i)) == 0)
            continue;

        const int row = (int)(i / 6u);
        const int col = (int)(i % 6u);
        const int x = enemy_x + col * 70;
        const int y = enemy_y + row * 48;
        const uint32_t color = row == 0 ? C_PINK : row == 2 ? C_BLUE : C_CYAN;

        draw_rect(x,      y,      32, 18, color);
        draw_rect(x + 6,  y - 5,   5,  6, color);
        draw_rect(x + 21, y - 5,   5,  6, color);
        draw_rect(x + 3,  y + 18,  6,  4, color);
        draw_rect(x + 23, y + 18,  6,  4, color);
        draw_rect(x + 7,  y + 7,   5,  5, C_DARK);
        draw_rect(x + 20, y + 7,   5,  5, C_DARK);
    }

    draw_rect(player_x,      430, 44, 12, C_BLUE);
    draw_rect(player_x + 11, 421, 22, 10, C_CYAN);
    draw_rect(player_x + 19, 413,  6, 10, C_WHITE);

    if (bullet_active)
        draw_rect(bullet_x, bullet_y, 4, 12, C_GREEN);
    if (eshot_active)
        draw_rect(eshot_x, eshot_y, 5, 12, C_RED);

    draw_text("A D MOVE SPACE FIRE ESC EXIT", 104, 457, C_DIM);

    if (game_state != 0) {
        draw_rect(148, 185, 344, 112, C_DARK);
        draw_rect(148, 185, 344,   3, C_FRAME);
        draw_rect(148, 294, 344,   3, C_FRAME);
        if (game_state == 1)
            draw_text("YOU WIN", 278, 209, C_GREEN);
        else
            draw_text("GAME OVER", 266, 209, C_RED);
        draw_text("R TO RESTART", 239, 254, C_WHITE);
    }
}

static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
{
    switch (message) {
    case WM_KEYDOWN:
        handle_key(wparam);
        return 0;

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        StretchDIBits(dc, 0, 0, WIDTH, HEIGHT, 0, 0, WIDTH, HEIGHT,
                      framebuffer, &bitmap_info, DIB_RGB_COLORS, SRCCOPY);
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_ERASEBKGND:
        return 1; // No flicker: we paint the entire client area.

    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        quit_game = 1;
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(hwnd, message, wparam, lparam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous,
                    PWSTR command_line, int show_command)
{
    (void)previous;
    (void)command_line;
    (void)SetProcessDPIAware();

    const wchar_t class_name[] = L"SpaceInvadersC17Window";
    WNDCLASSW wc = {0};
    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    wc.lpszClassName = class_name;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);

    if (RegisterClassW(&wc) == 0)
        return 1;

    const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    RECT rect = {0, 0, WIDTH, HEIGHT};
    if (!AdjustWindowRectEx(&rect, style, FALSE, 0))
        return 1;

    HWND hwnd = CreateWindowExW(
        0, class_name, L"Space Invaders - C17 / Win32", style,
        CW_USEDEFAULT, CW_USEDEFAULT, rect.right - rect.left,
        rect.bottom - rect.top, NULL, NULL, instance, NULL);

    if (hwnd == NULL)
        return 1;

    reset_game();
    render_game();
    ShowWindow(hwnd, show_command);
    UpdateWindow(hwnd);

    // The original app waits 16666 microseconds after rendering each frame.
    // A high-resolution waitable timer gives the Win32 version similar pacing.
    HANDLE timer = CreateWaitableTimerExW(
        NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
        TIMER_MODIFY_STATE | SYNCHRONIZE);
    if (timer == NULL)
        timer = CreateWaitableTimerW(NULL, FALSE, NULL);

    while (!quit_game) {
        // UEFI reads a maximum of 24 keyboard events per frame. Win32 messages
        // include nonkeyboard messages, so we drain its queue every frame.
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                quit_game = 1;
                break;
            }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        if (quit_game)
            break;
        if (game_state == 0)
            update_game();

        render_game();
        InvalidateRect(hwnd, NULL, FALSE);
        UpdateWindow(hwnd);

        if (timer != NULL) {
            LARGE_INTEGER delay;
            delay.QuadPart = -166660LL; // 16666 us in 100-ns intervals
            if (SetWaitableTimer(timer, &delay, 0, NULL, NULL, FALSE))
                WaitForSingleObject(timer, INFINITE);
            else
                Sleep(16);
        } else {
            Sleep(16);
        }
    }

    if (timer != NULL)
        CloseHandle(timer);
    if (IsWindow(hwnd))
        DestroyWindow(hwnd);
    return 0;
}
