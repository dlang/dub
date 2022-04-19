module something;

void doSomething() {
	import core.stdc.stdio;

	version(D_BetterC) {
		printf("druntime is not in the executable :(\n");
	} else {
		printf("druntime is in executable!\n");
	}
}
