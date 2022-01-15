
.PHONY: clean

dirac: dirac.o
	$(CC) $(CFLAGS) $^ -o $@

dirac.c: dirac.l
	lex -o dirac.c dirac.l

dirac.o: dirac.c
	$(CC) $(CFLAGS) -c $^ -o $@

clean:
	rm *.o dirac
