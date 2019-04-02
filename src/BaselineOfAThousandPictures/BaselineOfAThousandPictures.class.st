Class {
	#name : #BaselineOfAThousandPictures,
	#superclass : #BaselineOf,
	#category : #BaselineOfAThousandPictures
}

{ #category : #baselines }
BaselineOfAThousandPictures >> baseline: spec [
	<baseline>

	| corePackages |

	corePackages := #(
		#'AKG-AThousandPictures'
		).
	spec for: #common do: [ 
		spec blessing: #baseline.

		corePackages do: [ :each | spec package: each ].
		spec
			group: 'Core' with: corePackages;
			group: 'all' with: #(#Core);
			group: 'default' with: #(#all).
		]
]
