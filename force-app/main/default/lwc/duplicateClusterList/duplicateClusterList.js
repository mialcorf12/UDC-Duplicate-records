import { LightningElement, api, track, wire } from 'lwc';
import getClusterList from '@salesforce/apex/DuplicateClusterController.getClusterList';

export default class DuplicateClusterList extends LightningElement {
    @track clusters = [];
    @track totalCount = 0;
    @track pageNumber = 1;
    @track isLoadingMore = false;
    @track errorMessage = null;
    @track isWireResolved = false;

    _objectType = null;
    _status = 'Open';
    _minScore = 0;
    pageSize = 10;

    @api
    get objectType() {
        return this._objectType;
    }
    set objectType(value) {
        this._objectType = value;
        this.pageNumber = 1;
        this.clusters = [];
    }

    @api
    get status() {
        return this._status;
    }
    set status(value) {
        this._status = value;
        this.pageNumber = 1;
        this.clusters = [];
    }

    @api
    get minScore() {
        return this._minScore;
    }
    set minScore(value) {
        this._minScore = value;
        this.pageNumber = 1;
        this.clusters = [];
    }

    @wire(getClusterList, {
        objectType: '$_objectType',
        status: '$_status',
        minScore: '$_minScore',
        pageSize: '$pageSize',
        pageNumber: '$pageNumber'
    })
    wiredClusters({ data, error }) {
        this.isLoadingMore = false;
        this.errorMessage = null;
        this.isWireResolved = true;

        if (data) {
            const incoming = data.clusters || [];
            if (this.pageNumber === 1) {
                this.clusters = incoming;
            } else {
                this.clusters = [...this.clusters, ...incoming];
            }
            this.totalCount = data.totalCount || 0;
        } else if (error) {
            this.errorMessage = error.body
                ? error.body.message
                : 'An error occurred loading clusters.';
        }
    }

    get isLoading() {
        return !this.isWireResolved;
    }

    get hasClusters() {
        return this.clusters && this.clusters.length > 0;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get showLoadMore() {
        return this.clusters.length < this.totalCount;
    }

    handleLoadMore() {
        if (!this.showLoadMore || this.isLoadingMore) return;
        this.isLoadingMore = true;
        this.pageNumber = this.pageNumber + 1;
    }

    handleClusterSelect(event) {
        // Re-emit upward
        this.dispatchEvent(
            new CustomEvent('clusterselect', {
                detail: event.detail,
                bubbles: false,
                composed: false
            })
        );
    }
}
