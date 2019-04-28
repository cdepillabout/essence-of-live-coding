demos: build demo-sine demo-sine-change demo-sines-forever

demo-sine:
	stack exec DemoSine > DemoSine.txt

# I could make this by-file, but I don't know how how to tell it whether build has done something or not
demo-sines-forever:
	stack exec DemoSinesForever > DemoSinesForever.txt

demo-sine-change:
	stack exec DemoSineChange > DemoSineChange.txt

speedtest: build
	time stack exec SpeedTest

build:
	stack build

pdf: demos
	cd article && pdflatex -shell-escape -interact nonstopmode EssenceOfLiveCoding.lhs