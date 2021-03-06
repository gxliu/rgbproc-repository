#! /usr/bin/python
# Copyright (C) 2011, 2012 Jan Viktorin

class EOFException(Exception):
	pass

class ImageLoader:
	"""
	Loads file formated as follows:
	R0 G0 B0
	R1 G1 B1
	...

	where Ri, Gi and Bi represent i'th pixel of RGB color scheme.
	Skips comments starting with '--'
	"""
	def __init__(self, resolution, indata):
		self.indata = indata
		self.width  = resolution[0]
		self.height = resolution[1]

	def reset(self):
		try:
			self.indata.rewind()
			return True
		except AttributeError:
			return False

	def nextPixel(self):
		import re
		line = self.indata.readline()
		if line is None:
			return None

		line = line.strip()
		result = re.match("^([0-9]+) ([0-9]+) ([0-9]+)$", line)
		if result:
			return (int(result.group(1)), int(result.group(2)), int(result.group(3)))

		result = re.match("^--", line)
		if result:
			return self.nextPixel()

		raise Exception("Invalid line in input file: '" + line + "'")

	def nextLine(self):
		line = []
		for i in range(self.width):
			px = self.nextPixel()
			if px is None:
				break

			line.append(px)

		return line
	
class ImageWin:
	"""
	Reads lines from ImageLoader.
	Formats 3x3 windows based on the loaded lines.
	First and last column and first and last row are repeated so that the
	pixel in every window's center is that one loaded by ImageLoader.
	
	Thus printing the center pixel should provide identity:
	  0 1 2 3 4 -> Win -> print win[center] -> 0 1 2 3 4
	Filtering results in sequence of same length.
	"""
	def __init__(self, loader):
		self.loader = loader
		self.reset()

	def reset(self):
		self.loader.reset()
		self.lines = None
		self.px = 0
		self.ln = 0

	def nextLineOrException(self):
		line = self.loader.nextLine()
		if len(line) == 0:
			raise EOFException("End of file")
	
		return line

	def preloadLines(self):
		self.lines = []
		first = self.nextLineOrException()
		self.lines.append(first)
		self.lines.append(first)
		self.lines.append(self.nextLineOrException())

	def loadNextLine(self):
		if self.ln == self.loader.height - 1:
			self.lines[0] = self.lines[1]
			self.lines[1] = self.lines[2]
			self.lines[2] = self.lines[2]
		else:
			self.lines[0] = self.lines[1]
			self.lines[1] = self.lines[2]
			self.lines[2] = self.nextLineOrException()

	def nextPixel(self):
		win = self.nextWin()
		return win[1][1]

	def nextWin(self):
		if self.lines is None:
			self.preloadLines()
		elif self.px == self.loader.width:
			self.ln += 1
			self.loadNextLine()
			self.px = 0

		win = [[-1, -1, -1], [-1, -1, -1], [-1, -1, -1]]

		if self.px == 0:
			win[0][0] = self.lines[0][0]
			win[0][1] = self.lines[0][0]
			win[0][2] = self.lines[0][1]
			win[1][0] = self.lines[1][0]
			win[1][1] = self.lines[1][0]
			win[1][2] = self.lines[1][1]
			win[2][0] = self.lines[2][0]
			win[2][1] = self.lines[2][0]
			win[2][2] = self.lines[2][1]
		elif self.px == self.loader.width - 1:
			win[0][0] = self.lines[0][self.px - 1]
			win[0][1] = self.lines[0][self.px + 0]
			win[0][2] = self.lines[0][self.px + 0]
			win[1][0] = self.lines[1][self.px - 1]
			win[1][1] = self.lines[1][self.px + 0]
			win[1][2] = self.lines[1][self.px + 0]
			win[2][0] = self.lines[2][self.px - 1]
			win[2][1] = self.lines[2][self.px + 0]
			win[2][2] = self.lines[2][self.px + 0]
		else:
			win[0][0] = self.lines[0][self.px - 1]
			win[0][1] = self.lines[0][self.px + 0]
			win[0][2] = self.lines[0][self.px + 1]
			win[1][0] = self.lines[1][self.px - 1]
			win[1][1] = self.lines[1][self.px + 0]
			win[1][2] = self.lines[1][self.px + 1]
			win[2][0] = self.lines[2][self.px - 1]
			win[2][1] = self.lines[2][self.px + 0]
			win[2][2] = self.lines[2][self.px + 1]

		self.px += 1
		return win

class IdentityFilter:
	def __init__(self, win):
		self.win = win

	def nextPixel(self):
		return self.win.nextPixel()

class MedianFilter:
	def __init__(self, win):
		self.win = win

	def medianColor(self, matrix, i):
		l = []
		for row in matrix:
			for col in row:
				l.append(col[i])
		return sorted(l)[5]

	def nextPixel(self):
		matrix = self.win.nextWin()
		r = self.medianColor(matrix, 0)
		g = self.medianColor(matrix, 1)
		b = self.medianColor(matrix, 2)
		return (r, g, b)

class LowPassFilter:
	def __init__(self, win):
		self.win = win

	def lowPass(self, matrix, i):
		r  = 0
		r += matrix[0][0][i]
		r += matrix[0][1][i] * 2
		r += matrix[0][2][i]
		r += matrix[1][0][i] * 2
		r += matrix[1][1][i] * 4
		r += matrix[1][2][i] * 2
		r += matrix[2][0][i]
		r += matrix[2][1][i] * 2
		r += matrix[2][2][i]
		return int(r / 16)

	def nextPixel(self):
		matrix = self.win.nextWin()
		r = self.lowPass(matrix, 0)
		g = self.lowPass(matrix, 1)
		b = self.lowPass(matrix, 2)
		return (r, g, b)

class HighPassFilter:
	def __init__(self, win):
		self.win = win

	def highPass(self, matrix, i):
		a = -matrix[0][1][i]
		b = matrix[1][1][i] * 2
		c = -matrix[2][1][i]
		r = a + b + c

		return (r - (-510)) / 4

	def nextPixel(self):
		matrix = self.win.nextWin()
		r = self.highPass(matrix, 0)
		g = self.highPass(matrix, 1)
		b = self.highPass(matrix, 2)
		return (r, g, b)

class GrayScaleFilter:
	def __init__(self, win):
		self.win = win

	def convert(self, r, g, b):
		cr = (r * 30) / 100
		cg = (g * 59) / 100
		cb = (b * 11) / 100

		return int(cr + cg + cb)

	def nextPixel(self):
		pixel = self.win.nextPixel()
		c = self.convert(pixel[0], pixel[1], pixel[2])
		return (c, c, c)

class MatrixFileGen:
	def __init__(self, win):
		self.win = win

	def nextMatrix(self):
		matrix = self.win.nextWin()

		l = []
		for row in matrix:
			for col in row:
				l.append(col)

		return l

import sys

def genMatrix(win):
	gen = MatrixFileGen(win)

	try:
		for x in range(640):
			for y in range(480):
				matrix = gen.nextMatrix()
				for i in range(9):
					sys.stdout.write("%d %d %d " % matrix[i])
				print("")
	except EOFException as e:
		pass

def testFilter(impl):
	impl.win.reset()

	def testName(name):
		sys.stderr.write("== %s ==\n" % str(name))

	def px2str(px):
		return "%s %s %s" % px

	testName(impl.__class__.__name__)

	try:
		i = 0
		for x in range(640):
			for y in range(480):
				pixel = impl.nextPixel()
				print(px2str(pixel))

			i += 1
			sys.stderr.write("\rline...%d" % i)

	except EOFException as e:
		pass

	sys.stderr.write("\n")

def main(test, source = sys.stdin):
	#loader   = ImageLoader((10, 5), source)
	loader   = ImageLoader((640, 480), source)
	win      = ImageWin(loader)
	identity = IdentityFilter(win)
	median   = MedianFilter(win)
	lowPass  = LowPassFilter(win)
	gray     = GrayScaleFilter(win)
	highPass = HighPassFilter(win)

	if test == "identity" or test is None:
		testFilter(identity)
	elif test == "median":
		testFilter(median)
	elif test == "low-pass":
		testFilter(lowPass)
	elif test == "gray":
		testFilter(gray)
	elif test == "high-pass":
		testFilter(highPass)
	elif test == "gen-matrix":
		genMatrix(win)

class TestInData:
	"""
	Generates testing data:
	0 0 0
	1 1 1
	...
	"""
	def __init__(self, count = 640 * 480):
		self.i   = 0
		self.count = count

	def rewind(self):
		self.i = 0
		
	def readline(self):
		if self.i == self.count:
			return None

		r = self.i
		g = self.i
		b = self.i
		self.i   += 1
		return "%s %s %s" % (r, g ,b)

#main(TestInData(10 * 5))
main(sys.argv[1])

