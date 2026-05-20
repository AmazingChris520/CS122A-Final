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

void Game(pair<int, int> &currentPos, char display[8][8])
{
    if (currentPos == make_pair(5, 0)) {
        
    display[currentPos.first][currentPos.second] = ' ';
        currentPos = make_pair(0, 0);

    }
    else
    {
    display[currentPos.first][currentPos.second] = ' ';
        currentPos.first += 1;
    display[currentPos.first][currentPos.second] = 'O';
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

    while (true) {
        Game(currentPos, display);
        Display(display);

        std::this_thread::sleep_for(std::chrono::milliseconds(100)); // Delay for 1 second (1000 milliseconds)
    }

    return 0;
}