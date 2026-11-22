// Copyright 2024-2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Two-player tic-tac-toe on the console: players take turns typing the
// number of a free square (1-9); Z quits.

#include "console.h"
#include "tictactoe.h"

static const unsigned char lines[8][3] = {
	{0, 1, 2}, {3, 4, 5}, {6, 7, 8},        // rows
	{0, 3, 6}, {1, 4, 7}, {2, 5, 8},        // columns
	{0, 4, 8}, {2, 4, 6},                   // diagonals
};

static void draw(const char board[9])
{
	print("\n");
	for (int row = 0; row < 3; row++) {
		print("      |     |\n");
		for (int col = 0; col < 3; col++) {
			print("   ");
			print_char(board[row * 3 + col]);
			print(col < 2 ? "  |" : "\n");
		}
		print(row < 2 ? " _____|_____|_____\n" : "      |     |\n");
	}
	print("\n");
}

static int wins(const char board[9], char mark)
{
	for (int i = 0; i < 8; i++)
		if (board[lines[i][0]] == mark && board[lines[i][1]] == mark && board[lines[i][2]] == mark)
			return 1;
	return 0;
}

void tictactoe(void)
{
	char board[9];
	char mark = 'X';

	for (int i = 0; i < 9; i++)
		board[i] = '1' + i;

	print("\n--- Tic-tac-toe ---\n");
	print("Player 1 is X, player 2 is O. Type 1-9 to place your mark, Z to quit.\n");

	for (int moves = 0; ; ) {
		draw(board);
		print(mark == 'X' ? "Player 1 (X): " : "Player 2 (O): ");

		char key = get_char();
		print_char(key);
		print("\n");

		if (key == 'z' || key == 'Z')
			return;
		if (key < '1' || key > '9') {
			print("Type a number from 1 to 9.\n");
			continue;
		}
		if (board[key - '1'] == 'X' || board[key - '1'] == 'O') {
			print("That square is taken.\n");
			continue;
		}

		board[key - '1'] = mark;
		moves++;

		if (wins(board, mark)) {
			draw(board);
			print(mark == 'X' ? "Player 1 wins!\n" : "Player 2 wins!\n");
			return;
		}
		if (moves == 9) {
			draw(board);
			print("Draw.\n");
			return;
		}
		mark = mark == 'X' ? 'O' : 'X';
	}
}
