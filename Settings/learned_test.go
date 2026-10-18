package main

import "testing"

func TestCountLearnedCountsEachWordOnce(t *testing.T) {
	text := "#tick\t12.0\n" +
		"你好\tni hao\t3.0\t2.5\t11.0\n" +
		"中国\tzhong guo\t1.0\t1.0\t12.0\r\n" +
		"你好\tni hao\t1.0\t1.0\t4.0\n" + // the same word again
		"泥嚎\tni hao\t1.0\t1.0\t4.0\n" + // the same syllables, another word
		"\n" +
		"broken\tni\tx\t1\t1\n" + // not a number
		"short\tni\t1\t1\n" + // four fields
		"blank\t \t1\t1\t1\n" // no syllables
	if got := countLearned(text); got != 3 {
		t.Errorf("got %d, want 3", got)
	}
	if got := countLearned(""); got != 0 {
		t.Errorf("empty: got %d", got)
	}
}

func TestLearnedCountWithoutAFileIsZero(t *testing.T) {
	if got := learnedCount(t.TempDir()); got != 0 {
		t.Errorf("got %d", got)
	}
}
