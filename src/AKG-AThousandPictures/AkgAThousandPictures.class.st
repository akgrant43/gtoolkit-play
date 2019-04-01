"
!A Thousand Pictures

This class is the story of improving image display with GToolkit.

Creating a pillar file that has multiple images, e.g. jpg files, referenced and displayed will likely fail to scroll smoothly due to the delay while the images are being loaded and scaled in the UI process.

A quick look at the code suggests several potential improvements:

- Load images in a background process.  A template should be shown until the image is loaded (may be blank).
- ZnBufferedReadStream>>upToEnd currently grows a ByteArray 64K at a time, so a 3MB image grows the ByteArray 48 times (to be confirmed), generating a lot of copying and garbage.
-- Ask the stream for it's size, nil on error.  Get the size, then anything remaining.
- Keep thumbnails of the images to reduce the file I/O.
- Does ImageReadWriter class>>gtFormFromFileReference: really need to wrap the stream in a ZnPositionableReadStream?  ZnBufferedReadStream will position: if the underlying stream does.


!!Baseline Performance 

First off, measure the load speed of jpg files using ImageReadWriter.  PluginBasedJPEGReadWriter uses stream #upToEnd to get the contents of the file.


[[[language=smalltalk
ImageReadWriter class>>gtFormFromFileReference: aFileReference
	<return: #Form>
	^ aFileReference binaryReadStreamDo: [ :aStream | 
			| aPositionableReadStream |
			aPositionableReadStream := ZnPositionableReadStream on: aStream.
			ImageReadWriter formFromStream: aPositionableReadStream ]	
]]]

and

[[[language=smalltalk
ImageReadWriter class>>formFromStream: aBinaryReadStream
	""Answer a Form of the image stored on aBinaryReadStream.
	This will (normally) autodetect the format and delegate to the correct concrete subclass.
	Closes aBinaryReadStream when done.""
	
	""ImageReadWriter formFromStream: 'test.png' asFileReference binaryReadStream""
	""ImageReadWriter formFromStream: 'test.jpg' asFileReference binaryReadStream""

	| positionableReadStream reader readerClass form |
	positionableReadStream := ZnPositionableReadStream on: aBinaryReadStream.
	readerClass := self readerClassFromStream: positionableReadStream.
	reader := readerClass new on: positionableReadStream.
	form := reader nextImage.
	aBinaryReadStream close.
	^ form	
]]]

We can see that getting the data as a ByteArray can be done with: 

[[[language=smalltalk
| byteArray aFileReference |

aFileReference binaryReadStreamDo: [ :stream | | bStream |
	bStream := ZnPositionableReadStream on: 
		(ZnPositionableReadStream on: 
			stream).
	byteArray := bStream upToEnd].
]]]


On my Dell XPS13 9333 (2012 model):

[[[language=smalltalk
AkgAThousandPictures new bench01: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ]).
'330.35 kB: 1016 at 33.82607537621521/s
1.56 MB: 198 at 6.59780073308897/s
4.14 MB: 58 at 1.927550681289465/s
'
]]]

First optimisation, remove the unnecessary ZnPositionableReadStreams:

[[[language=smalltalk
AkgAThousandPictures new bench02: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ])

 '330.35 kB: 26563 at 885.403819872671/s
1.56 MB: 461 at 15.340077199520831/s
4.14 MB: 126 at 4.183128050197537/s
'
]]]


Check the number of times the write buffer is grown while reading i4.0M.jpg:

[[[language=smalltalk
AkgAThousandPictures new bench03: '/dev/shm/pics/i4.0M.jpg' asFileReference
 'Number of log entries: 15
'
]]]




[[[language=smalltalk
AkgAThousandPictures new bench04: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ])

 '330.35 kB: 158614 at 5286.604672866047/s
1.56 MB: 2047 at 68.19468967585036/s
4.14 MB: 562 at 18.71773522064946/s
'
]]]
"
Class {
	#name : #AkgAThousandPictures,
	#superclass : #Object,
	#category : #'AKG-AThousandPictures'
}

{ #category : #benchmarking }
AkgAThousandPictures >> bench01: fileCollection [
	"Benchmark the set of supplied files using the original stream structure as it exists in Pharo 7 April 2019"

	| reportStream |

	reportStream := String new writeStream.
	fileCollection do: [ :file | | bench |
		3 timesRepeat: [ Smalltalk garbageCollect ].
		bench := [ file asFileReference binaryReadStreamDo: [ :stream | | bStream |
			bStream := ZnPositionableReadStream on: 
				(ZnPositionableReadStream on: 
					stream).
		bStream upToEnd] ] benchFor: 30 seconds.
		file asFileReference size humanReadableSIByteSizeOn: reportStream.
		reportStream
			<< ': ';
			print: bench iterations;
			<< ' at ';
			print: bench frequency asFloat;
			<< '/s';
			cr ].
	^reportStream contents
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench02: fileCollection [
	"Benchmark the set of supplied files using streams not wrapped in ZnPositionableReadStream"

	| reportStream |

	reportStream := String new writeStream.
	fileCollection do: [ :file | | bench |
		3 timesRepeat: [ Smalltalk garbageCollect ].
		bench := [ file asFileReference binaryReadStreamDo: [ :stream |
			stream upToEnd] ] benchFor: 30 seconds.
		file asFileReference size humanReadableSIByteSizeOn: reportStream.
		reportStream
			<< ': ';
			print: bench iterations;
			<< ' at ';
			print: bench frequency asFloat;
			<< '/s';
			cr ].
	^reportStream contents
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench03: aFileReference [
	"Count the number of buffer expansions performed by ZnBufferedReadStream when reading the entire contents of the supplied file"

	| logger contents |

	logger := MemoryLogger new.
	logger runDuring: [ aFileReference asFileReference binaryReadStreamDo:
		[ :stream | contents := stream upToEnd ] ].
	self assert: contents size = aFileReference asFileReference size.
	^String streamContents: [ :stream |
		stream 
			<< 'Number of log entries: ';
			print: logger recordings size;
			cr ]
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench04: fileCollection [
	"Benchmark the set of supplied files using:
	- streams not wrapped in ZnPositionableReadStream
	- Proposed #upToEnd modification (Use #next: file size)"

	| reportStream |

	reportStream := String new writeStream.
	fileCollection do: [ :file | | bench |
		3 timesRepeat: [ Smalltalk garbageCollect ].
		bench := [ file asFileReference binaryReadStreamDo: [ :stream | | contents |
			contents := stream next: file asFileReference size.
			"#upToEnd would check to see if at end and get anything that is missing.
			Short-cut for now by checking that the entire contents were in fact retrieved."
			self assert: stream atEnd.
			self assert: contents size = file asFileReference size.
			] ] benchFor: 30 seconds.
		file asFileReference size humanReadableSIByteSizeOn: reportStream.
		reportStream
			<< ': ';
			print: bench iterations;
			<< ' at ';
			print: bench frequency asFloat;
			<< '/s';
			cr ].
	^reportStream contents
]
