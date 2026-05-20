#include <iostream>
#include <utility>
#include <chrono>
#include <thread>

using namespace std;

enum gameState {
    START,
    PLAYING,
    GAME_OVER
}; // Only playing for now

void Display(char display[8][8])
{

    system("cls"); // Clear the console (works on Windows, for Unix/Linux use "clear")
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
            cout << display[i][j];
        }
        cout << endl;
    }
}

void Game(pair<int, int> &currentPos, char display[8][8], bool direction)
{
    if (currentPos == make_pair(7, 0)) {
        
    display[currentPos.first][currentPos.second] = ' ';
        currentPos = make_pair(0, 0);

    }
    else
    {
    display[currentPos.first][currentPos.second] = ' ';
        currentPos.first += 1;
    display[currentPos.first][currentPos.second] = 'O';

    if (direction) {
        if (currentPos.second < 7)
        currentPos.second += 1;
    }
    else {
        if (currentPos.second > 0)
        currentPos.second -= 1;
    }
}
}

void movement(bool right)
{
    char movement;
    cin >> movement;

    if (movement == 'w') {
        // Move up
    }
    else if (movement == 's') {
        // Move down
    }
    else if (movement == 'a') {
        right = 0;
    }
    else if (movement == 'd') {
        right = 1;
    }
}

int main() {
    cout << "Hello, World!" << endl;

    char display[8][8] = {
        {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '},
        {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '},
        {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '},
        {' ', ' ', ' ', 'X', 'X', 'X', 'X', 'X'},
        {' ', ' ', ' ', 'X', 'X', 'X', 'X', 'X'},
        {' ', ' ', ' ', 'X', 'X', 'X', 'X', 'X'},
        {' ', ' ', ' ', 'X', 'X', 'X', 'X', 'X'},
        {' ', ' ', ' ', 'X', 'X', 'X', 'X', 'X'}
    };

    pair <int, int> currentPos = make_pair(0, 0);

    bool direction = 1; // 1 for right, 0 for left
    while (true) {
        movement(direction);
        Game(currentPos, display, direction);
        Display(display);

        std::this_thread::sleep_for(std::chrono::milliseconds(100)); // Delay for 1 second (1000 milliseconds)
    }

    return 0;
}