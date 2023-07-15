version (FromCli1)
	enum has1 = true;
else
	enum has1 = false;

version (FromCli2)
	enum has2 = true;
else
	enum has2 = false;

static assert(has1);
static assert(has2);

void main()
{
}
