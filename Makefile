
.PHONY: clean

dirac: dirac.o
	gcc $^ -o $@

dirac.c: dirac.l
	lex -o dirac.c dirac.l

dirac.o: dirac.c
	cc $(CFLAGS) -c $^ -o $@

clean:
	rm *.o dirac
