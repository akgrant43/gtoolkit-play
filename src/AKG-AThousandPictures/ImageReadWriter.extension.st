Extension { #name : #ImageReadWriter }

{ #category : #'*AKG-AThousandPictures' }
ImageReadWriter class >> formFromStream: aBinaryReadStream [
	"Answer a Form of the image stored on aBinaryReadStream.
	This will (normally) autodetect the format and delegate to the correct concrete subclass.
	Closes aBinaryReadStream when done."
	
	"ImageReadWriter formFromStream: 'test.png' asFileReference binaryReadStream"
	"ImageReadWriter formFromStream: 'test.jpg' asFileReference binaryReadStream"

	| reader readerClass form |
	readerClass := self readerClassFromStream: aBinaryReadStream.
	reader := readerClass new on: aBinaryReadStream.
	form := reader nextImage.
	aBinaryReadStream close.
	^ form
]

{ #category : #'*AKG-AThousandPictures' }
ImageReadWriter class >> gtFormFromFileReference: aFileReference [
	<return: #Form>
	^ aFileReference binaryReadStreamDo: [ :aStream | 
			self formFromStream: aStream ]
]
